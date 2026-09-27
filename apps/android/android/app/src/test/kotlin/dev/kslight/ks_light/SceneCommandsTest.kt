package dev.kslight.ks_light

import org.junit.Assert.*
import org.junit.Test

class SceneCommandsTest {
    @Test fun mixedSceneCalibratesOnlyOnMembersAndAllOffNeedsNoColor() {
        val color = FavoriteColor(200, 100, 50, 128)
        val members = listOf(SceneMember("first", true, color), SceneMember("second", false, color))
        val calibrated = mutableListOf<String>()
        val scene = sceneCommands(members, true) { address, snapshot ->
            calibrated.add(address); snapshot.packet(listOf(0.5, 1.0, 1.0), "RGB")
        }
        assertEquals(listOf("first"), calibrated)
        assertEquals(2, scene[0].packets.size)
        assertEquals(100, scene[0].packets[1][3].toInt())
        assertFalse(scene[1].on)
        assertEquals(1, scene[1].packets.size)
        val off = sceneCommands(members, false) { _, _ -> error("Off must not require calibration") }
        assertTrue(off.all { !it.on && it.packets.size == 1 && it.packets[0][1] == 0x0f.toByte() })
        assertThrows(IllegalArgumentException::class.java) { sceneCommands(members + members[0], true) { _, _ -> byteArrayOf() } }
        assertThrows(IllegalArgumentException::class.java) { sceneCommands(emptyList(), true) { _, _ -> byteArrayOf() } }
    }
}
