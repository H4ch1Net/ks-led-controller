package com.ksled.controller.vm

import android.app.Application
import android.graphics.Color
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ksled.controller.ble.ConnectionState
import com.ksled.controller.ble.KsBleManager
import com.ksled.controller.ble.KsProtocol
import com.ksled.controller.ble.ScannedDevice
import com.ksled.controller.data.AppRepository
import com.ksled.controller.data.Preset
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.sin
import kotlin.random.Random

/** Immutable snapshot of the control surface. */
data class UiState(
    val powerOn: Boolean = true,
    val hue: Float = 0f,          // 0..360
    val saturation: Float = 1f,   // 0..1
    val brightness: Float = 1f,   // 0..1
    val animation: AnimationType = AnimationType.NONE,
    val speed: Float = 0.5f,      // 0..1
)

class ControllerViewModel(app: Application) : AndroidViewModel(app) {

    val ble = KsBleManager(app)
    private val repo = AppRepository(app)

    val scanResults: StateFlow<List<ScannedDevice>> = ble.scanResults
    val isScanning: StateFlow<Boolean> = ble.isScanning
    val connectionState: StateFlow<ConnectionState> = ble.connectionState

    val presets: StateFlow<List<Preset>> = repo.presets
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val nicknames: StateFlow<Map<String, String>> = repo.nicknames
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyMap())

    private val _ui = MutableStateFlow(UiState())
    val ui: StateFlow<UiState> = _ui.asStateFlow()

    private var animationJob: Job? = null

    private val style: KsProtocol.Style?
        get() = (connectionState.value as? ConnectionState.Connected)?.device?.model?.style

    // ------------------------------------------------------------- Connection

    fun startScan() = ble.startScan()
    fun stopScan() = ble.stopScan()
    fun connect(device: ScannedDevice) = ble.connect(device)
    fun disconnect() {
        stopAnimation()
        ble.disconnect()
    }

    // ------------------------------------------------------------- Power / color

    fun togglePower(on: Boolean) {
        _ui.value = _ui.value.copy(powerOn = on)
        if (!on) stopAnimation()
        ble.send(KsProtocol.onOff(on))
        if (on) pushCurrentColor()
    }

    fun setHue(hue: Float) {
        stopAnimation()
        _ui.value = _ui.value.copy(hue = hue.coerceIn(0f, 360f))
        pushCurrentColor()
    }

    fun setSaturation(sat: Float) {
        stopAnimation()
        _ui.value = _ui.value.copy(saturation = sat.coerceIn(0f, 1f))
        pushCurrentColor()
    }

    /** Set hue + saturation together from the colour wheel. */
    fun setHueSaturation(hue: Float, sat: Float) {
        stopAnimation()
        _ui.value = _ui.value.copy(
            hue = hue.coerceIn(0f, 360f),
            saturation = sat.coerceIn(0f, 1f),
        )
        pushCurrentColor()
    }

    fun setBrightness(value: Float) {
        _ui.value = _ui.value.copy(brightness = value.coerceIn(0f, 1f))
        // Brightness applies live even during animations.
        if (_ui.value.animation == AnimationType.NONE) pushCurrentColor()
    }

    fun applyPreset(preset: Preset) {
        stopAnimation()
        val hsv = FloatArray(3)
        Color.RGBToHSV(preset.r, preset.g, preset.b, hsv)
        _ui.value = _ui.value.copy(
            powerOn = true,
            hue = hsv[0],
            saturation = hsv[1],
        )
        ble.send(KsProtocol.onOff(true))
        pushCurrentColor()
    }

    private fun currentRgb(): Triple<Int, Int, Int> {
        val s = _ui.value
        val color = Color.HSVToColor(floatArrayOf(s.hue, s.saturation, 1f))
        return Triple(Color.red(color), Color.green(color), Color.blue(color))
    }

    private fun pushCurrentColor() {
        val st = style ?: return
        if (!_ui.value.powerOn) return
        val (r, g, b) = currentRgb()
        val brightnessByte = (_ui.value.brightness * 255).toInt()
        ble.send(KsProtocol.color(r, g, b, st, brightnessByte))
    }

    private fun sendColor(hue: Float, sat: Float, brightness: Float) {
        val st = style ?: return
        val color = Color.HSVToColor(floatArrayOf(hue, sat, 1f))
        ble.send(
            KsProtocol.color(
                Color.red(color), Color.green(color), Color.blue(color),
                st, (brightness.coerceIn(0f, 1f) * 255).toInt(),
            )
        )
    }

    // ------------------------------------------------------------- Presets

    fun savePreset(name: String) = viewModelScope.launch {
        val (r, g, b) = currentRgb()
        val updated = presets.value.filter { it.name != name } + Preset(name, r, g, b)
        repo.savePresets(updated)
    }

    fun deletePreset(preset: Preset) = viewModelScope.launch {
        repo.savePresets(presets.value.filter { it.name != preset.name })
    }

    fun setNickname(address: String, nickname: String?) = viewModelScope.launch {
        repo.setNickname(address, nickname)
    }

    // ------------------------------------------------------------- Animations

    fun startAnimation(type: AnimationType) {
        if (type == AnimationType.NONE) {
            stopAnimation()
            return
        }
        animationJob?.cancel()
        _ui.value = _ui.value.copy(animation = type, powerOn = true)
        ble.send(KsProtocol.onOff(true))
        animationJob = viewModelScope.launch { runAnimation(type) }
    }

    fun setSpeed(value: Float) {
        _ui.value = _ui.value.copy(speed = value.coerceIn(0f, 1f))
    }

    private fun stopAnimation() {
        animationJob?.cancel()
        animationJob = null
        if (_ui.value.animation != AnimationType.NONE) {
            _ui.value = _ui.value.copy(animation = AnimationType.NONE)
        }
    }

    /** Frame interval in ms derived from the speed slider (fast = small). */
    private fun frameDelay(min: Long, max: Long): Long {
        val s = _ui.value.speed
        return (max - (max - min) * s).toLong()
    }

    private suspend fun runAnimation(type: AnimationType) {
        var hue = _ui.value.hue
        var phase = 0.0
        while (currentCoroutineContext().isActive) {
            val bright = _ui.value.brightness
            when (type) {
                AnimationType.RAINBOW -> {
                    hue = (hue + 4f) % 360f
                    sendColor(hue, 1f, bright)
                    delay(frameDelay(40, 220))
                }
                AnimationType.BREATHE -> {
                    phase += 0.12
                    val level = ((sin(phase) + 1) / 2).toFloat() * bright
                    sendColor(_ui.value.hue, _ui.value.saturation, level.coerceIn(0.02f, 1f))
                    delay(frameDelay(40, 160))
                }
                AnimationType.STROBE -> {
                    sendColor(_ui.value.hue, _ui.value.saturation, bright)
                    delay(frameDelay(30, 120))
                    sendColor(_ui.value.hue, _ui.value.saturation, 0f)
                    delay(frameDelay(30, 120))
                }
                AnimationType.FLASH -> {
                    hue = (hue + 60f) % 360f
                    sendColor(hue, 1f, bright)
                    delay(frameDelay(120, 600))
                }
                AnimationType.FIRE -> {
                    val h = 10f + Random.nextFloat() * 30f      // red-orange
                    val level = (0.5f + Random.nextFloat() * 0.5f) * bright
                    sendColor(h, 1f, level)
                    delay(frameDelay(60, 200))
                }
                AnimationType.CANDLE -> {
                    val h = 30f + Random.nextFloat() * 12f      // warm amber
                    val level = (0.45f + Random.nextFloat() * 0.35f) * bright
                    sendColor(h, 0.85f, level)
                    delay(frameDelay(90, 260))
                }
                AnimationType.OCEAN -> {
                    phase += 0.05
                    val h = 190f + (sin(phase) * 40f).toFloat()  // teal-blue sweep
                    sendColor(h, 0.9f, bright)
                    delay(frameDelay(60, 220))
                }
                AnimationType.NONE -> return
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        ble.shutdown()
    }
}
