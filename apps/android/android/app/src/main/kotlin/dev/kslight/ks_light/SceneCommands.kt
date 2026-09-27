package dev.kslight.ks_light

internal data class SceneMember(val address: String, val power: Boolean, val color: FavoriteColor?)
internal data class ShortcutStep(val address: String, val on: Boolean, val packets: List<ByteArray>)

/** Complete the immutable plan before any Bluetooth connection or partial scene delivery. */
internal fun sceneCommands(members: List<SceneMember>, apply: Boolean,
                          colorPacket: (String, FavoriteColor) -> ByteArray): List<ShortcutStep> {
    require(members.size in 1..8 && members.map { it.address }.toSet().size == members.size)
    return members.map { member ->
        val on = apply && member.power
        val power = byteArrayOf(0x5b, (if (on) 0xf0 else 0x0f).toByte(), 1, 0xb5.toByte())
        val color = if (on && member.color != null) colorPacket(member.address, member.color) else null
        ShortcutStep(member.address, on, if (color == null) listOf(power) else listOf(power, color))
    }
}
