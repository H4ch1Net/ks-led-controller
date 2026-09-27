package dev.kslight.ks_light

import org.junit.Assert.*
import org.junit.Test

class FavoriteColorTest {
    @Test fun encodesFloorColorAndBrightnessWithoutChangingSnapshot() {
        val favorite = FavoriteColor(239, 66, 255, 128)
        assertEquals("#EF42FF", favorite.hex)
        assertArrayEquals(byteArrayOf(0x5a, 0, 1, 239.toByte(), 66, 255.toByte(), 0, 50, 0, 0xa5.toByte()),
            favorite.packet(listOf(1.0, 1.0, 1.0), "RGB"))
        // Gains affect logical channels before the lamp's channel order is applied.
        assertArrayEquals(byteArrayOf(0x5a, 0, 1, 64, 33, 120, 0, 50, 0, 0xa5.toByte()),
            favorite.packet(listOf(0.5, 0.5, 0.25), "BGR"))
        assertEquals(FavoriteColor(239, 66, 255, 128), favorite)
    }

    @Test fun rejectsInvalidSnapshotAndCalibrationBeforeDelivery() {
        assertThrows(IllegalArgumentException::class.java) { FavoriteColor(256, 0, 0, 255) }
        assertThrows(IllegalArgumentException::class.java) { FavoriteColor(0, 0, 0, -1) }
        val favorite = FavoriteColor(100, 100, 100, 255)
        assertThrows(IllegalArgumentException::class.java) { favorite.packet(listOf(1.0, Double.NaN, 1.0), "RGB") }
        assertThrows(IllegalArgumentException::class.java) { favorite.packet(listOf(1.0, 1.0, 1.1), "RGB") }
        assertThrows(IllegalArgumentException::class.java) { favorite.packet(listOf(1.0, 1.0), "RGB") }
        assertThrows(IllegalArgumentException::class.java) { favorite.packet(listOf(1.0, 1.0, 1.0), "RRR") }
    }
}
