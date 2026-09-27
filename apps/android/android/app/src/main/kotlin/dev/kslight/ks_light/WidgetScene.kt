package dev.kslight.ks_light

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

internal data class WidgetScene(val name: String, val members: List<SceneMember>) {
    fun json(): String {
        val states = JSONObject()
        members.forEach { member ->
            val state = JSONObject().put("power", member.power)
            if (member.color != null) state.put("rgb", org.json.JSONArray(listOf(member.color.red, member.color.green, member.color.blue)))
                .put("brightness", member.color.brightness)
            else state.put("brightness", 255)
            states.put(member.address, state)
        }
        return JSONObject().put("name", name).put("states", states).toString()
    }
    companion object {
        fun parse(name: String, states: JSONObject): WidgetScene {
            require(name.isNotBlank() && name.length <= 40 && states.length() in 1..8)
            val members = states.keys().asSequence().map { address ->
                require(android.bluetooth.BluetoothAdapter.checkBluetoothAddress(address))
                val state = states.getJSONObject(address)
                require(state.get("power") is Boolean && state.get("brightness") is Int)
                val brightness = state.getInt("brightness")
                require(brightness in 0..255)
                val rgb = if (state.isNull("rgb")) null else state.getJSONArray("rgb")
                val color = if (rgb == null) null else {
                    require(rgb.length() == 3 && (0..2).all { rgb.get(it) is Int })
                    FavoriteColor(rgb.getInt(0), rgb.getInt(1), rgb.getInt(2), brightness)
                }
                SceneMember(address, state.getBoolean("power"), color)
            }.toList()
            return WidgetScene(name, members)
        }
        fun saved(prefs: SharedPreferences): WidgetScene? = try {
            val raw = prefs.getString("scene", null)
            if (raw == null || raw.length > 16384) null else {
                val value = JSONObject(raw)
                parse(value.getString("name"), value.getJSONObject("states"))
            }
        } catch (_: Exception) { null }
        fun available(context: Context): List<WidgetScene> = try {
            val library = JSONObject(context.getSharedPreferences("light_settings", Context.MODE_PRIVATE).getString("library_real", "{}") ?: "{}")
            val scenes = library.optJSONObject("scenes") ?: JSONObject()
            scenes.keys().asSequence().mapNotNull { name ->
                try { parse(name, scenes.getJSONObject(name)).takeIf { scene -> scene.members.all { Shortcuts.savedWidgetTarget(context, it.address) } } }
                catch (_: Exception) { null }
            }.toList()
        } catch (_: Exception) { emptyList() }
    }
}
