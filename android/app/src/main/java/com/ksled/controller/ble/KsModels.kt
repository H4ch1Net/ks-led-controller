package com.ksled.controller.ble

import java.util.UUID

/**
 * Static registry mapping KS device name prefixes to their GATT service /
 * write-characteristic short UUIDs and command wire-format.
 *
 * Derived from UUIDBeanList in the decompiled app and the Python reference
 * implementation. The 16-bit short UUIDs are expanded with the standard
 * Bluetooth base UUID.
 */
data class KsModel(
    val prefix: String,
    val service: String,
    val write: String,
    val style: KsProtocol.Style,
) {
    val serviceUuid: UUID get() = shortUuid(service)
    val writeUuid: UUID get() = shortUuid(write)

    companion object {
        private const val BASE = "0000%s-0000-1000-8000-00805f9b34fb"

        fun shortUuid(short: String): UUID = UUID.fromString(BASE.format(short.lowercase()))

        val ALL: List<KsModel> = listOf(
            KsModel("KS03~", "AFD0", "AFD1", KsProtocol.Style.FLOOR_5A),
            KsModel("KS15~", "AFD0", "AFD3", KsProtocol.Style.FLOOR_5A),
            KsModel("KS03-", "FFF0", "FFF3", KsProtocol.Style.STRIP_7E),
            KsModel("KS04-", "FFF0", "FFF3", KsProtocol.Style.STRIP_7E),
            KsModel("KS01-", "AE00", "AE01", KsProtocol.Style.STRIP_7E),
            KsModel("KS02-", "AE00", "AE01", KsProtocol.Style.STRIP_7E),
            KsModel("KS04~", "AE00", "AE10", KsProtocol.Style.STRIP_7E),
            KsModel("KS05-", "AE00", "AE02", KsProtocol.Style.STRIP_7E),
            KsModel("KS07-", "AE00", "AE10", KsProtocol.Style.STRIP_7E),
            KsModel("KS08-", "AE00", "AE10", KsProtocol.Style.STRIP_7E),
            KsModel("KS09-", "AE00", "AE10", KsProtocol.Style.STRIP_7E),
            KsModel("KS10-", "AE00", "AE10", KsProtocol.Style.STRIP_7E),
            KsModel("KS11-", "AE00", "AE10", KsProtocol.Style.STRIP_7E),
            KsModel("KS12-", "AE00", "AE10", KsProtocol.Style.STRIP_7E),
            KsModel("KS13-", "AE00", "AE10", KsProtocol.Style.STRIP_7E),
        )

        /** Device name prefixes we consider "ours" while scanning. */
        val PREFIXES: List<String> = ALL.map { it.prefix }

        fun matches(name: String?): KsModel? {
            if (name == null) return null
            return ALL.firstOrNull { name.startsWith(it.prefix) }
        }
    }
}
