package dev.kslight.ks_light

import org.junit.Assert.*
import org.junit.Test

class ShortcutTargetPolicyTest {
    private val first = "BE:60:4D:00:58:37"
    private val second = "BE:60:4D:00:58:38"
    @Test fun separateWidgetsAcceptTheirOwnTargets() {
        assertTrue(ShortcutTargetPolicy.accepts(10, setOf(10, 20), first, first))
        assertTrue(ShortcutTargetPolicy.accepts(20, setOf(10, 20), second, second))
        assertFalse(ShortcutTargetPolicy.accepts(20, setOf(10, 20), second, first))
    }
    @Test fun reassignedWidgetRejectsOldTap() {
        assertFalse(ShortcutTargetPolicy.accepts(10, setOf(10), second, first))
    }
    @Test fun reconfiguredFavoriteRejectsOldTapEvenForTheSameLight() {
        assertFalse(ShortcutTargetPolicy.accepts(10, setOf(10), first, first, "new", "old"))
        assertTrue(ShortcutTargetPolicy.accepts(10, setOf(10), first, first, "new", "new"))
    }
    @Test fun deletedWidgetRejectsQueuedTap() {
        assertFalse(ShortcutTargetPolicy.accepts(10, setOf(20), first, first))
    }
    @Test fun removedDeviceCannotReceiveCommand() {
        assertFalse(ShortcutTargetPolicy.accepts(10, setOf(10), "", first))
        assertFalse(ShortcutTargetPolicy.accepts(-1, emptySet(), "", null))
    }
    @Test fun sharedTileTargetDoesNotRequireWidget() {
        assertTrue(ShortcutTargetPolicy.accepts(-1, emptySet(), first, first))
        assertFalse(ShortcutTargetPolicy.accepts(-1, emptySet(), second, first))
    }
    @Test fun legacyControlWithoutSnapshotStillRequiresLiveTarget() {
        assertTrue(ShortcutTargetPolicy.accepts(-1, emptySet(), first, null))
        assertFalse(ShortcutTargetPolicy.accepts(10, emptySet(), first, null))
    }
}
