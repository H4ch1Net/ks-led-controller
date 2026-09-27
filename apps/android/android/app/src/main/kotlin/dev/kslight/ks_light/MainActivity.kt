package dev.kslight.ks_light

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val documents by lazy { BackupDocuments(this) }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (!documents.onResult(requestCode, resultCode, data)) super.onActivityResult(requestCode, resultCode, data)
    }
    override fun onDestroy() {
        documents.close()
        super.onDestroy()
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val preferences = getSharedPreferences("light_settings", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.kslight/settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "diagnostics" -> result.success(Diagnostics.snapshot(this))
                    "loadHubPairing", "saveHubPairing", "forgetHubPairing" -> {
                        try {
                            val pairing = HubPairing(this)
                            when (call.method) {
                                "loadHubPairing" -> result.success(pairing.load())
                                "saveHubPairing" -> {
                                    pairing.save(call.argument<String>("address") ?: error("Missing address"),
                                        call.argument<String>("token") ?: error("Missing token"))
                                    result.success(null)
                                }
                                else -> { pairing.forget(); result.success(null) }
                            }
                        } catch (_: Exception) { result.error("PAIRING_FAILED", "Saved hub pairing is unavailable. Forget it and pair again.", null) }
                    }
                    "exportLibraryFile" -> {
                        val text = call.arguments as? String
                        if (text == null) result.error("INVALID", "Expected backup text", null)
                        else documents.launch(text, result)
                    }
                    "importLibraryFile" -> documents.launch(null, result)
                    "acquireBluetooth" -> {
                        val key = ShortcutLock.acquire()
                        if(key == null) result.error("BUSY", "A light command is already running", null) else result.success(key)
                    }
                    "releaseBluetooth" -> { (call.arguments as? String)?.let { ShortcutLock.release(it) }; result.success(null) }
                    "shortcutPower" -> {
                        val id = call.argument<String>("id"); val on = call.argument<Boolean>("on")
                        if(id != null && on != null) Shortcuts.record(this, id, on)
                        result.success(null)
                    }
                    "configureShortcuts" -> {
                        val id = call.argument<String>("id"); val name = call.argument<String>("name")
                        if(id == null || !android.bluetooth.BluetoothAdapter.checkBluetoothAddress(id) || name.isNullOrBlank()) result.error("INVALID", "Select a real KS03 light first", null)
                        else {
                            Shortcuts.migrateWidgets(this)
                            val p = Shortcuts.prefs(this)
                            if(p.getString("address", null) != id) p.edit().remove("last_on").apply()
                            p.edit().putString("address", id).putString("name", name.take(80)).putString("status", "Ready; state not verified").commit()
                            Shortcuts.update(this); result.success(null)
                        }
                    }
                    "pinWidget" -> {
                        val manager = android.appwidget.AppWidgetManager.getInstance(this)
                        Shortcuts.migrateWidgets(this)
                        val p = Shortcuts.prefs(this)
                        val callback = android.content.Intent(this, LightWidget::class.java).setAction("dev.kslight.WIDGET_PINNED")
                            .setData(android.net.Uri.parse("kslight://pin/" + java.util.UUID.randomUUID()))
                            .putExtra("address", p.getString("address", "")).putExtra("name", p.getString("name", "KS Light"))
                        val callbackFlags = android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                            if (android.os.Build.VERSION.SDK_INT >= 31) android.app.PendingIntent.FLAG_MUTABLE else 0
                        val pinned = android.app.PendingIntent.getBroadcast(this, 0, callback, callbackFlags)
                        result.success(android.os.Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported && manager.requestPinAppWidget(android.content.ComponentName(this, LightWidget::class.java), null, pinned))
                    }
                    "addDeviceControl" -> {
                        if(android.os.Build.VERSION.SDK_INT >= 30 && Shortcuts.configured(this)) {
                            val p = Shortcuts.prefs(this)
                            val name = p.getString("name", "KS Light") ?: "KS Light"
                            val control = android.service.controls.Control.StatelessBuilder(
                                "power:" + p.getString("address", ""), Shortcuts.activity(this))
                                .setTitle(if(name.startsWith("KS03~")) "KS Light" else name)
                                .setSubtitle("Bluetooth light").setStructure("KS Light")
                                .setDeviceType(android.service.controls.DeviceTypes.TYPE_LIGHT).build()
                            android.service.controls.ControlsProviderService.requestAddControl(
                                this, android.content.ComponentName(this, LightDeviceControls::class.java), control)
                            result.success(true)
                        } else result.success(false)
                    }
                    "addTile" -> {
                        if(android.os.Build.VERSION.SDK_INT >= 33) {
                            getSystemService(android.app.StatusBarManager::class.java).requestAddTileService(android.content.ComponentName(this, LightPowerTile::class.java), "KS Light", android.graphics.drawable.Icon.createWithResource(this, R.drawable.ic_light_tile), mainExecutor) { }
                            result.success(true)
                        } else result.success(false)
                    }
                    "loadAppPreferences" -> result.success(preferences.getString("app_preferences", null))
                    "saveAppPreferences" -> {
                        val value = call.arguments as? String
                        if (value == null || value.length > 32768) result.error("INVALID", "Invalid app preferences", null)
                        else if (preferences.edit().putString("app_preferences", value).commit()) result.success(null)
                        else result.error("SAVE_FAILED", "Could not save preferences", null)
                    }
                    "load" -> result.success(preferences.getString("devices", null))
                    "save" -> {
                        val value = call.arguments as? String
                        if (value == null) result.error("INVALID", "Expected settings JSON", null)
                        else if (preferences.edit().putString("devices", value).commit()) result.success(null)
                        else result.error("SAVE_FAILED", "Could not save light settings", null)
                    }
                    "loadLibrary" -> {
                        val key = if (call.arguments == true) "library_demo" else "library_real"
                        result.success(preferences.getString(key, null))
                    }
                    "saveLibrary" -> {
                        val value = call.argument<String>("json")
                        val key = if (call.argument<Boolean>("demo") == true) "library_demo" else "library_real"
                        if (value == null) result.error("INVALID", "Expected library JSON", null)
                        else {
                            val shortcutPrefs = Shortcuts.prefs(this)
                            val target = shortcutPrefs.getString("address", null)
                            val oldLights = try { org.json.JSONObject(preferences.getString(key, "{}") ?: "{}").optJSONObject("lights") } catch (_: Exception) { null }
                            val newLights = try { org.json.JSONObject(value).getJSONObject("lights") } catch (_: Exception) { null }
                            if (newLights == null) result.error("INVALID", "Invalid lighting library", null)
                            else if (preferences.edit().putString(key, value).commit()) {
                                if (call.argument<Boolean>("demo") != true && target != null && oldLights?.has(target) == true && !newLights.has(target)) {
                                    shortcutPrefs.edit().remove("address").remove("name").remove("last_on").putString("status", "Tap to set up").apply()
                                    Shortcuts.update(this)
                                }
                                if (call.argument<Boolean>("demo") != true) Shortcuts.removeMissingWidgets(this, oldLights, newLights)
                                result.success(null)
                            } else result.error("SAVE_FAILED", "Could not save lighting library", null)
                        }
                    }
                    "loadNativeEffects" -> {
                        val id = call.arguments as? String
                        if (id.isNullOrBlank()) result.error("INVALID", "Expected light ID", null)
                        else result.success(preferences.getString("native_effects_" + id, null))
                    }
                    "saveNativeEffects" -> {
                        val id = call.argument<String>("id")
                        val value = call.argument<String>("json")
                        if (id.isNullOrBlank() || value == null) result.error("INVALID", "Expected light ID and effect JSON", null)
                        else if (preferences.edit().putString("native_effects_" + id, value).commit()) result.success(null)
                        else result.error("SAVE_FAILED", "Could not save effect settings", null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
