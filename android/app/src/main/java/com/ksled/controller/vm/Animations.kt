package com.ksled.controller.vm

/** Built-in app-side animations. KS firmware exposes no native effect commands,
 *  so these are driven by streaming colour frames over BLE from the phone. */
enum class AnimationType(val label: String, val icon: String) {
    NONE("Solid", "●"),
    RAINBOW("Rainbow", "🌈"),
    BREATHE("Breathe", "💨"),
    STROBE("Strobe", "⚡"),
    FLASH("Colour Flash", "✨"),
    FIRE("Fire", "🔥"),
    CANDLE("Candle", "🕯"),
    OCEAN("Ocean", "🌊"),
}
