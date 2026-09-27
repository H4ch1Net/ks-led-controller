package dev.kslight.ks_light

/** A queued tap must still refer to the same live shortcut and target. */
internal object ShortcutTargetPolicy {
    fun accepts(widgetId: Int, liveWidgetIds: Set<Int>, address: String, expectedAddress: String?,
                revision: String? = null, expectedRevision: String? = null): Boolean =
        address.isNotBlank() && (widgetId == -1 || widgetId in liveWidgetIds) &&
            (expectedAddress == null || expectedAddress == address) &&
            (expectedRevision == null || expectedRevision == revision)
}
