package dev.kslight.ks_light

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

/** Read-only, allowlisted snapshot: no addresses, names, credentials or network calls. */
internal object Diagnostics {
    fun snapshot(context: Context): Map<String, Any?> {
        fun granted(permission: String) = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        val connect = Build.VERSION.SDK_INT < 31 || granted(Manifest.permission.BLUETOOTH_CONNECT)
        val scan = if (Build.VERSION.SDK_INT >= 31) granted(Manifest.permission.BLUETOOTH_SCAN)
                   else granted(Manifest.permission.ACCESS_FINE_LOCATION)
        val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter
        val enabled = if (connect) try { adapter?.isEnabled } catch (_: SecurityException) { null } else null
        return mapOf(
            "androidApi" to Build.VERSION.SDK_INT,
            "bluetoothSupported" to (adapter != null),
            "bluetoothEnabled" to enabled,
            "connectPermission" to connect,
            "scanPermission" to scan,
            "bluetoothBusy" to ShortcutLock.isBusy(),
            "widgets" to Shortcuts.widgetIds(context).size,
            "quickControlsConfigured" to Shortcuts.configured(context),
        )
    }
}
