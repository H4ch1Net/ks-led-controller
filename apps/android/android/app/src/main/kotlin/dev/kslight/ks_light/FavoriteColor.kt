package dev.kslight.ks_light

import kotlin.math.roundToInt

/** Logical, uncalibrated snapshot. Balance is applied once, at command time. */
internal data class FavoriteColor(val red: Int, val green: Int, val blue: Int, val brightness: Int) {
    init { require(listOf(red, green, blue, brightness).all { it in 0..255 }) }
    val hex: String get() = "#%02X%02X%02X".format(red, green, blue)
    fun packet(gains: List<Double>, order: String): ByteArray {
        require(gains.size == 3 && gains.all { it.isFinite() && it in 0.0..1.0 })
        require(order in listOf("RGB", "RBG", "GRB", "GBR", "BRG", "BGR"))
        val logical = listOf(red, green, blue)
        val adjusted = logical.mapIndexed { index, value -> (value * gains[index]).roundToInt() }
        val channels = order.map { adjusted["RGB".indexOf(it)] }
        return byteArrayOf(0x5a, 0, 1, channels[0].toByte(), channels[1].toByte(), channels[2].toByte(),
            0, (brightness * 100.0 / 255).roundToInt().toByte(), 0, 0xa5.toByte())
    }
}
