package com.ksled.controller.ble

/**
 * Command builders for KS LED devices.
 *
 * All byte sequences below were reverse-engineered from the official KS/KeepSmile
 * Android app and mirror the Python reference implementation shipped in this repo
 * (led_control.py / led_menu.py).
 *
 *  - ON / OFF  : 5BF001B5 / 5B0F01B5
 *  - Colour (5A / "floor" lamps, has a brightness byte):
 *        5A 0001 RR GG BB 00 BB 00A5
 *  - Colour (7E / "strip/ceiling" lamps, no brightness byte):
 *        7E 070503 RR GG BB 00 EF
 *  - Brightness only, white mode (5A lamps):
 *        5A 000200000000 BB 00A5
 */
object KsProtocol {

    /** Command wire-format families exposed by the different KS models. */
    enum class Style { FLOOR_5A, STRIP_7E }

    fun onOff(on: Boolean): ByteArray =
        hex(if (on) "5BF001B5" else "5B0F01B5")

    /**
     * Build a colour command.
     *
     * @param brightness 0..255. For FLOOR_5A this is sent as a dedicated byte and the
     *   raw RGB is preserved. For STRIP_7E there is no brightness field, so brightness
     *   is folded into the RGB values by scaling.
     */
    fun color(r: Int, g: Int, b: Int, style: Style, brightness: Int = 255): ByteArray {
        val rr = r.coerceIn(0, 255)
        val gg = g.coerceIn(0, 255)
        val bb = b.coerceIn(0, 255)
        val br = brightness.coerceIn(0, 255)
        return when (style) {
            Style.FLOOR_5A ->
                hex("5A0001%02X%02X%02X00%02X00A5".format(rr, gg, bb, br))
            Style.STRIP_7E -> {
                val sr = rr * br / 255
                val sg = gg * br / 255
                val sb = bb * br / 255
                hex("7E070503%02X%02X%02X00EF".format(sr, sg, sb))
            }
        }
    }

    /** Brightness in white mode. Only meaningful for FLOOR_5A lamps. */
    fun brightnessWhite(brightness: Int, style: Style): ByteArray {
        val br = brightness.coerceIn(0, 255)
        return when (style) {
            Style.FLOOR_5A -> hex("5A000200000000%02X00A5".format(br))
            // Strip lamps have no white-mode brightness command; emit a warm-white
            // scaled by brightness instead so the slider still does something useful.
            Style.STRIP_7E -> color(255, 147, 41, style, br)
        }
    }

    private fun hex(s: String): ByteArray {
        val clean = s.replace(" ", "")
        return ByteArray(clean.length / 2) {
            clean.substring(it * 2, it * 2 + 2).toInt(16).toByte()
        }
    }
}
