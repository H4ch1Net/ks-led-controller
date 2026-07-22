package com.ksled.controller.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import org.json.JSONArray
import org.json.JSONObject

private val Context.dataStore by preferencesDataStore(name = "ks_led_prefs")

/**
 * Persists user presets and per-device nicknames using Jetpack DataStore.
 * Values are encoded as JSON strings with the platform [org.json] APIs so the
 * app needs no extra serialization dependency.
 */
class AppRepository(context: Context) {

    private val store = context.applicationContext.dataStore

    private val presetsKey = stringPreferencesKey("presets")
    private val nicknamesKey = stringPreferencesKey("nicknames")

    val presets: Flow<List<Preset>> = store.data.map { prefs ->
        prefs[presetsKey]?.let(::decodePresets) ?: DefaultPresets.list
    }

    val nicknames: Flow<Map<String, String>> = store.data.map { prefs ->
        prefs[nicknamesKey]?.let(::decodeNicknames) ?: emptyMap()
    }

    suspend fun savePresets(presets: List<Preset>) {
        store.edit { it[presetsKey] = encodePresets(presets) }
    }

    suspend fun setNickname(address: String, nickname: String?) {
        store.edit { prefs ->
            val current = prefs[nicknamesKey]?.let(::decodeNicknames)?.toMutableMap()
                ?: mutableMapOf()
            if (nickname.isNullOrBlank()) current.remove(address) else current[address] = nickname
            prefs[nicknamesKey] = encodeNicknames(current)
        }
    }

    // ------------------------------------------------------------ JSON helpers

    private fun encodePresets(presets: List<Preset>): String {
        val arr = JSONArray()
        presets.forEach { p ->
            arr.put(
                JSONObject()
                    .put("name", p.name)
                    .put("r", p.r)
                    .put("g", p.g)
                    .put("b", p.b)
            )
        }
        return arr.toString()
    }

    private fun decodePresets(raw: String): List<Preset> = runCatching {
        val arr = JSONArray(raw)
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            Preset(o.getString("name"), o.getInt("r"), o.getInt("g"), o.getInt("b"))
        }
    }.getOrDefault(DefaultPresets.list)

    private fun encodeNicknames(map: Map<String, String>): String {
        val o = JSONObject()
        map.forEach { (k, v) -> o.put(k, v) }
        return o.toString()
    }

    private fun decodeNicknames(raw: String): Map<String, String> = runCatching {
        val o = JSONObject(raw)
        o.keys().asSequence().associateWith { o.getString(it) }
    }.getOrDefault(emptyMap())
}
