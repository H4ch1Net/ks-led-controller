package com.ksled.controller.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** A KS device discovered during a scan. */
data class ScannedDevice(
    val address: String,
    val name: String,
    val model: KsModel,
    val rssi: Int,
)

sealed interface ConnectionState {
    data object Idle : ConnectionState
    data class Connecting(val device: ScannedDevice) : ConnectionState
    data class Connected(val device: ScannedDevice) : ConnectionState
    data class Failed(val device: ScannedDevice?, val reason: String) : ConnectionState
}

/**
 * Owns all Bluetooth interaction: scanning for KS devices, maintaining a single
 * GATT connection and serialising characteristic writes through a queue.
 *
 * Callers are responsible for holding the appropriate runtime permissions before
 * invoking [startScan]/[connect]; the methods are annotated to suppress the lint
 * checks because permission gating happens in the UI layer.
 */
@SuppressLint("MissingPermission")
class KsBleManager(private val appContext: Context) {

    private val scope = CoroutineScope(SupervisorJob())
    private val bluetoothManager =
        appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?
    private val adapter: BluetoothAdapter? = bluetoothManager?.adapter

    private val _scanResults = MutableStateFlow<List<ScannedDevice>>(emptyList())
    val scanResults: StateFlow<List<ScannedDevice>> = _scanResults.asStateFlow()

    private val _isScanning = MutableStateFlow(false)
    val isScanning: StateFlow<Boolean> = _isScanning.asStateFlow()

    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Idle)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    val isBluetoothEnabled: Boolean get() = adapter?.isEnabled == true

    private var gatt: BluetoothGatt? = null
    private var writeChar: BluetoothGattCharacteristic? = null
    private var connectingDevice: ScannedDevice? = null

    // Serialised write pipeline. New commands overwrite the oldest queued command
    // when the device is slower than the UI (e.g. during animations) so we never
    // fall behind the current colour.
    private val writeQueue = Channel<ByteArray>(
        capacity = 16,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    init {
        scope.launch { writeLoop() }
    }

    // ---------------------------------------------------------------- Scanning

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device ?: return
            val name = device.name ?: result.scanRecord?.deviceName ?: return
            val model = KsModel.matches(name) ?: return
            val entry = ScannedDevice(device.address, name, model, result.rssi)
            _scanResults.value = (_scanResults.value.filter { it.address != entry.address } + entry)
                .sortedByDescending { it.rssi }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.w(TAG, "Scan failed: $errorCode")
            _isScanning.value = false
        }
    }

    fun startScan() {
        val scanner = adapter?.bluetoothLeScanner ?: return
        if (_isScanning.value) return
        _scanResults.value = emptyList()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        _isScanning.value = true
        // Scan without filters and match by name prefix in the callback; KS devices
        // do not advertise a consistent service UUID across all models.
        scanner.startScan(null, settings, scanCallback)
    }

    fun stopScan() {
        if (!_isScanning.value) return
        adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        _isScanning.value = false
    }

    // -------------------------------------------------------------- Connection

    fun connect(device: ScannedDevice) {
        disconnect()
        stopScan()
        connectingDevice = device
        _connectionState.value = ConnectionState.Connecting(device)
        val remote = adapter?.getRemoteDevice(device.address) ?: run {
            _connectionState.value = ConnectionState.Failed(device, "Bluetooth unavailable")
            return
        }
        gatt = remote.connectGatt(appContext, false, gattCallback, BluetoothDevice_TRANSPORT_LE)
    }

    fun disconnect() {
        writeChar = null
        gatt?.let {
            it.disconnect()
            it.close()
        }
        gatt = null
        if (_connectionState.value !is ConnectionState.Failed) {
            _connectionState.value = ConnectionState.Idle
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    g.discoverServices()
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    writeChar = null
                    g.close()
                    if (gatt === g) gatt = null
                    val dev = connectingDevice
                    _connectionState.value =
                        if (status == BluetoothGatt.GATT_SUCCESS) ConnectionState.Idle
                        else ConnectionState.Failed(dev, "Disconnected (status $status)")
                }
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            val device = connectingDevice
            if (status != BluetoothGatt.GATT_SUCCESS || device == null) {
                _connectionState.value = ConnectionState.Failed(device, "Service discovery failed")
                return
            }
            val target = resolveWriteCharacteristic(g, device.model)
            if (target == null) {
                _connectionState.value =
                    ConnectionState.Failed(device, "Write characteristic not found")
                return
            }
            writeChar = target
            _connectionState.value = ConnectionState.Connected(device)
        }
    }

    /** Look up the model's write characteristic, falling back to a global search. */
    private fun resolveWriteCharacteristic(
        g: BluetoothGatt,
        model: KsModel,
    ): BluetoothGattCharacteristic? {
        g.getService(model.serviceUuid)?.getCharacteristic(model.writeUuid)?.let { return it }
        for (service in g.services) {
            service.getCharacteristic(model.writeUuid)?.let { return it }
            service.characteristics.firstOrNull {
                it.properties and (BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
            }?.let { return it }
        }
        return null
    }

    // ------------------------------------------------------------------ Writes

    /** Enqueue a command. Silently ignored when not connected. */
    fun send(command: ByteArray) {
        if (writeChar == null || gatt == null) return
        writeQueue.trySend(command)
    }

    private suspend fun writeLoop() {
        for (command in writeQueue) {
            val g = gatt
            val ch = writeChar
            if (g == null || ch == null) continue
            performWrite(g, ch, command)
            // Small settle delay keeps flaky KS firmwares from dropping commands.
            kotlinx.coroutines.delay(35)
        }
    }

    private fun performWrite(
        g: BluetoothGatt,
        ch: BluetoothGattCharacteristic,
        command: ByteArray,
    ) {
        val writeType =
            if (ch.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0)
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            else BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeCharacteristic(ch, command, writeType)
            } else {
                @Suppress("DEPRECATION")
                ch.writeType = writeType
                @Suppress("DEPRECATION")
                ch.value = command
                @Suppress("DEPRECATION")
                g.writeCharacteristic(ch)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Write failed: ${t.message}")
        }
    }

    fun shutdown() {
        stopScan()
        disconnect()
    }

    companion object {
        private const val TAG = "KsBleManager"
        // BluetoothDevice.TRANSPORT_LE == 2; referenced by literal to avoid an import
        // clash with the enclosing class name.
        private const val BluetoothDevice_TRANSPORT_LE = 2
    }
}
