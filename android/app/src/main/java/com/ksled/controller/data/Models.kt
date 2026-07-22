package com.ksled.controller.data

/** A saved colour preset. */
data class Preset(
    val name: String,
    val r: Int,
    val g: Int,
    val b: Int,
)

object DefaultPresets {
    val list: List<Preset> = listOf(
        Preset("Warm White", 255, 147, 41),
        Preset("Cool White", 201, 226, 255),
        Preset("Daylight", 255, 250, 244),
        Preset("Red", 255, 0, 0),
        Preset("Orange", 255, 165, 0),
        Preset("Yellow", 255, 255, 0),
        Preset("Green", 0, 255, 0),
        Preset("Cyan", 0, 255, 255),
        Preset("Blue", 0, 0, 255),
        Preset("Purple", 128, 0, 128),
        Preset("Magenta", 255, 0, 255),
        Preset("Pink", 255, 105, 180),
    )
}
