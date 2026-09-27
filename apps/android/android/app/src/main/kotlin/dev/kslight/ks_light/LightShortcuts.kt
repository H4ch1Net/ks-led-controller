package dev.kslight.ks_light

import android.Manifest
import android.app.*
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.bluetooth.*
import android.content.*
import android.content.pm.PackageManager
import android.os.*
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.RemoteViews
import java.util.UUID

object ShortcutLock {
    private var owner: String? = null
    @Synchronized fun acquire(): String? {
        if (owner != null) return null
        return UUID.randomUUID().toString().also { owner = it }
    }
    @Synchronized fun release(key: String) { if (owner == key) owner = null }
    @Synchronized fun isBusy(): Boolean = owner != null
}

object Shortcuts {
    fun prefs(c: Context) = c.getSharedPreferences("shortcuts", Context.MODE_PRIVATE)
    fun widgetPrefs(c: Context, id: Int) = c.getSharedPreferences("widget_$id", Context.MODE_PRIVATE)
    fun widgetIds(c: Context) = AppWidgetManager.getInstance(c).getAppWidgetIds(ComponentName(c, LightWidget::class.java))
    fun configured(c: Context) = BluetoothAdapter.checkBluetoothAddress(prefs(c).getString("address", "") ?: "")
    fun migrateWidgets(c: Context) {
        val p = prefs(c)
        if (p.getBoolean("widgets_migrated", false)) return
        widgetIds(c).forEach { id ->
            val w = widgetPrefs(c, id)
            if (!w.contains("initialized") && configured(c)) {
                w.edit().putBoolean("initialized", true).putString("address", p.getString("address", ""))
                    .putString("name", p.getString("name", "KS Light"))
                    .putString("status", p.getString("status", "Ready")).commit()
            }
        }
        p.edit().putBoolean("widgets_migrated", true).commit()
    }
    fun savedWidgetTarget(c: Context, address: String): Boolean {
        if (!BluetoothAdapter.checkBluetoothAddress(address)) return false
        return try {
            val raw = c.getSharedPreferences("light_settings", Context.MODE_PRIVATE).getString("library_real", "{}")
            org.json.JSONObject(raw ?: "{}").optJSONObject("lights")?.optJSONObject(address)?.optString("prefix") == "KS03~"
        } catch (_: Exception) { false }
    }
    private fun deviceSettings(c: Context, address: String): org.json.JSONObject? {
        val raw = c.getSharedPreferences("light_settings", Context.MODE_PRIVATE).getString("devices", "{}")
        return org.json.JSONObject(raw ?: "{}").optJSONObject(address)
    }
    internal fun lastColor(c: Context, address: String): FavoriteColor? = try {
        val settings = deviceSettings(c, address)
        val rgb = settings?.optJSONArray("lastColor")
        if (rgb == null || rgb.length() != 3 || (0..2).any { rgb.get(it) !is Int } || settings.opt("lastBrightness") !is Int) null
        else FavoriteColor(rgb.getInt(0), rgb.getInt(1), rgb.getInt(2), settings.getInt("lastBrightness"))
    } catch (_: Exception) { null }
    internal fun colorPacket(c: Context, address: String, favorite: FavoriteColor): ByteArray {
        val settings = deviceSettings(c, address)
        val raw = settings?.optJSONArray("gains")
        val gains = if (raw == null) listOf(1.0, 1.0, 1.0) else {
            require(raw.length() == 3 && (0..2).all { raw.get(it) is Number })
            (0..2).map { raw.getDouble(it) }
        }
        return favorite.packet(gains, settings?.optString("order", "RGB") ?: "RGB")
    }
    internal fun widgetColor(p: SharedPreferences): FavoriteColor? = if (!p.contains("favorite_red")) null else try {
        FavoriteColor(p.getInt("favorite_red", -1), p.getInt("favorite_green", -1),
            p.getInt("favorite_blue", -1), p.getInt("favorite_brightness", -1))
    } catch (_: Exception) { null }
    internal fun assignWidget(c: Context, id: Int, address: String, name: String, favorite: FavoriteColor? = null): Boolean {
        if (id !in widgetIds(c) || !savedWidgetTarget(c, address)) return false
        val edit = widgetPrefs(c, id).edit().clear().putBoolean("initialized", true).putString("address", address)
            .putString("name", name).putString("revision", UUID.randomUUID().toString()).putString("status", "Ready")
        if (favorite != null) edit.putInt("favorite_red", favorite.red).putInt("favorite_green", favorite.green)
            .putInt("favorite_blue", favorite.blue).putInt("favorite_brightness", favorite.brightness)
        val saved = edit.commit()
        update(c)
        return saved
    }
    internal fun assignScene(c: Context, id: Int, scene: WidgetScene): Boolean {
        if (id !in widgetIds(c) || !scene.members.all { savedWidgetTarget(c, it.address) }) return false
        val saved = widgetPrefs(c, id).edit().clear().putBoolean("initialized", true)
            .putString("address", "scene:${scene.name}").putString("name", scene.name).putString("scene", scene.json())
            .putString("revision", UUID.randomUUID().toString()).putString("status", "Ready").commit()
        update(c)
        return saved
    }
    internal fun sceneStatus(c: Context, id: Int, revision: String?, status: String, results: String? = null) {
        if (id !in widgetIds(c)) return
        val prefs = widgetPrefs(c, id)
        if (prefs.getString("revision", null) != revision) return
        val edit = prefs.edit().putString("status", status)
        if (results != null) edit.putString("scene_results", results)
        edit.apply()
        update(c)
    }
    fun activity(c: Context): PendingIntent = PendingIntent.getActivity(c, 0,
        Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun configureWidget(c: Context, id: Int): PendingIntent = PendingIntent.getActivity(c, id,
        Intent(c, WidgetSetupActivity::class.java).setData(android.net.Uri.parse("kslight://widget/$id/setup"))
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun command(c: Context, on: Boolean, widgetId: Int = -1): PendingIntent {
        val source = if (widgetId == -1) prefs(c) else widgetPrefs(c, widgetId)
        val address = source.getString("address", "") ?: ""
        val i = Intent(c, ShortcutPowerService::class.java).putExtra("on", on)
            .putExtra("widget_id", widgetId).putExtra("expected_address", address)
            .putExtra("expected_revision", source.getString("revision", null))
            .putExtra("favorite", widgetId != -1 && on && widgetColor(source) != null)
            .putExtra("scene", widgetId != -1 && source.contains("scene"))
            .setData(android.net.Uri.parse("kslight://power/$widgetId/$address/$on"))
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (Build.VERSION.SDK_INT >= 26) PendingIntent.getForegroundService(c, 0, i, flags)
               else PendingIntent.getService(c, 0, i, flags)
    }
    fun update(c: Context, message: String? = null) {
        migrateWidgets(c)
        if (message != null) prefs(c).edit().putString("status", message).apply()
        val manager = AppWidgetManager.getInstance(c)
        widgetIds(c).forEach { id ->
            val p = widgetPrefs(c, id)
            val views = RemoteViews(c.packageName, R.layout.light_widget)
            val name = p.getString("name", "Choose light") ?: "Choose light"
            val status = p.getString("status", "Tap to set up") ?: "Tap to set up"
            val scene = WidgetScene.saved(p)
            val valid = scene != null || BluetoothAdapter.checkBluetoothAddress(p.getString("address", "") ?: "")
            val favorite = widgetColor(p)
            views.setTextViewText(R.id.light_name, if(name.startsWith("KS03~")) "KS Light" else name)
            views.setTextViewText(R.id.light_status, status.replace("Last sent:", "Sent:").replace("Ready; state not verified", "Ready"))
            views.setTextViewText(R.id.light_on, if (scene != null) "Scene" else if (favorite == null) "On" else "Color")
            views.setContentDescription(R.id.light_on, if (scene != null) "Apply saved scene ${scene.name}" else if (favorite == null) "Turn light on" else "Apply favorite ${favorite.hex} and turn on")
            views.setContentDescription(R.id.light_off, if (scene != null) "Turn off all ${scene.members.size} scene lights" else "Turn light off")
            if (favorite != null && status == "Ready") views.setTextViewText(R.id.light_status, "Favorite ${favorite.hex}")
            if (scene != null && status == "Ready") views.setTextViewText(R.id.light_status, "${scene.members.size} lights · Saved scene")
            views.setContentDescription(R.id.light_details, "$name. $status. Choose widget light")
            views.setOnClickPendingIntent(R.id.light_details, configureWidget(c, id))
            views.setOnClickPendingIntent(R.id.light_name, configureWidget(c, id))
            views.setOnClickPendingIntent(R.id.light_on, if(valid) command(c, true, id) else configureWidget(c, id))
            views.setOnClickPendingIntent(R.id.light_off, if(valid) command(c, false, id) else configureWidget(c, id))
            manager.updateAppWidget(id, views)
        }
        TileService.requestListeningState(c, ComponentName(c, LightPowerTile::class.java))
    }
    fun report(c: Context, address: String, message: String, on: Boolean? = null) {
        val targets = widgetIds(c).map { widgetPrefs(c, it) } + prefs(c)
        targets.filter { address.isNotEmpty() && it.getString("address", null) == address }.forEach { p ->
            val edit = p.edit().putString("status", message)
            if (on != null) edit.putBoolean("last_on", on)
            edit.apply()
        }
        update(c)
    }
    fun record(c: Context, address: String, on: Boolean) = report(c, address, "Last sent: " + if(on) "On" else "Off", on)
    fun removeMissingWidgets(c: Context, old: org.json.JSONObject?, fresh: org.json.JSONObject) {
        migrateWidgets(c)
        widgetIds(c).forEach { id ->
            val p = widgetPrefs(c, id)
            val address = p.getString("address", null)
            val removedSceneMember = WidgetScene.saved(p)?.members?.any { !fresh.has(it.address) } == true
            if (removedSceneMember || address != null && old?.has(address) == true && !fresh.has(address)) {
                p.edit().clear().putBoolean("initialized", true).putString("status", "Light removed; tap to set up").apply()
            }
        }
        update(c)
    }
}

class LightWidget : AppWidgetProvider() {
    override fun onUpdate(c: Context, manager: AppWidgetManager, ids: IntArray) = Shortcuts.update(c)
    override fun onDeleted(c: Context, ids: IntArray) { ids.forEach { Shortcuts.widgetPrefs(c, it).edit().clear().apply() } }
    override fun onReceive(c: Context, intent: Intent) {
        super.onReceive(c, intent)
        if (intent.action == "dev.kslight.WIDGET_PINNED") {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
            val address = intent.getStringExtra("address") ?: return
            if (id in Shortcuts.widgetIds(c) && BluetoothAdapter.checkBluetoothAddress(address))
                Shortcuts.assignWidget(c, id, address, intent.getStringExtra("name") ?: "KS Light")
        }
    }
}

class LightPowerTile : TileService() {
    override fun onStartListening() {
        val p = Shortcuts.prefs(this)
        val configured = Shortcuts.configured(this)
        val known = configured && p.contains("last_on")
        val on = known && p.getBoolean("last_on", false)
        val status = p.getString("status", "") ?: ""
        val summary = when {
            !configured -> "Choose a light"
            status == "Sending…" -> "Sending…"
            status.isNotEmpty() && !status.startsWith("Last sent:") && status != "Ready; state not verified" -> "Retry in app"
            !known -> "Tap to turn on"
            on -> "On"
            else -> "Off"
        }
        qsTile?.apply {
            val name = p.getString("name", "KS Light") ?: "KS Light"
            label = if (name.startsWith("KS03~")) "KS Light" else name
            // Optimistic state from the last completed write, not lamp readback.
            state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            if (Build.VERSION.SDK_INT >= 29) subtitle = summary
            contentDescription = "$label. $summary. " +
                if (known) "Last successful command. Tap to turn ${if (on) "off" else "on"}." else "Open or control your light."
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        if (isLocked) { unlockAndRun { send() }; return }
        send()
    }
    private fun send() {
        if (!Shortcuts.configured(this)) {
            if(Build.VERSION.SDK_INT >= 34) startActivityAndCollapse(Shortcuts.activity(this))
            else { @Suppress("DEPRECATION") startActivityAndCollapse(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            return
        }
        try { Shortcuts.command(this, !Shortcuts.prefs(this).getBoolean("last_on", false)).send() }
        catch (_: Exception) { Shortcuts.update(this, "Open app to retry") }
    }
}

class ShortcutPowerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var gatt: BluetoothGatt? = null
    private var owner: String? = null
    private var done = true
    private var address = ""
    private var on = false
    private var packets = emptyList<ByteArray>()
    private var packetIndex = 0
    private var awaitingWrite = false
    private var writeTarget: BluetoothGattCharacteristic? = null
    private var writeMode = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
    private var steps = emptyList<ShortcutStep>()
    private var stepIndex = 0
    private var sentCount = 0
    private var sceneWidgetId = -1
    private var sceneRevision: String? = null
    private var sceneResults = org.json.JSONArray()
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!done) return START_NOT_STICKY // Do not queue repeated taps.
        if (intent == null || !intent.hasExtra("on")) { stopSelf(); return START_NOT_STICKY }
        val widgetId = intent.getIntExtra("widget_id", -1)
        val source = if (widgetId == -1) Shortcuts.prefs(this) else Shortcuts.widgetPrefs(this, widgetId)
        address = source.getString("address", "") ?: ""
        if (!ShortcutTargetPolicy.accepts(widgetId, Shortcuts.widgetIds(this).toSet(), address,
                intent.getStringExtra("expected_address"), source.getString("revision", null),
                intent.getStringExtra("expected_revision"))) { stopSelf(); return START_NOT_STICKY }
        sceneWidgetId = if (intent.getBooleanExtra("scene", false)) widgetId else -1
        sceneRevision = source.getString("revision", null)
        val allowed = Build.VERSION.SDK_INT < 31 || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        if (!allowed) { Shortcuts.report(this, address, "Open app: Bluetooth permission needed"); stopSelf(); return START_NOT_STICKY }
        try {
            val nm = getSystemService(NotificationManager::class.java)
            if(Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel("light_commands", "Light commands", NotificationManager.IMPORTANCE_LOW))
            val builder = if(Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "light_commands") else Notification.Builder(this)
            startForeground(43, builder.setSmallIcon(R.drawable.ic_light_tile).setContentTitle("KS Light")
                .setContentText("Sending light command…").setContentIntent(Shortcuts.activity(this)).build())
            owner = ShortcutLock.acquire()
            if(owner == null) { Shortcuts.report(this, address, "Light busy — stop the active effect or retry"); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY }
            done = false
            on = intent.getBooleanExtra("on", false)
            steps = emptyList(); stepIndex = 0; sentCount = 0; sceneResults = org.json.JSONArray()
            val power = byteArrayOf(0x5b, (if(on) 0xf0 else 0x0f).toByte(), 1, 0xb5.toByte())
            if (sceneWidgetId != -1) {
                val scene = WidgetScene.saved(source)
                if (scene == null || !scene.members.all { Shortcuts.savedWidgetTarget(this, it.address) }) {
                    finish(false, "Scene unavailable; tap widget name"); return START_NOT_STICKY
                }
                // Validate/build every member before the first connection/write.
                steps = sceneCommands(scene.members, on) { target, color -> Shortcuts.colorPacket(this, target, color) }
            } else {
              packets = if (intent.getBooleanExtra("favorite", false)) {
                if (!on || widgetId == -1 || !Shortcuts.savedWidgetTarget(this, address)) {
                    finish(false, "Favorite unavailable; tap widget name"); return START_NOT_STICKY
                }
                val favorite = Shortcuts.widgetColor(source)
                if (favorite == null) { finish(false, "Favorite unavailable; tap widget name"); return START_NOT_STICKY }
                listOf(power, Shortcuts.colorPacket(this, address, favorite))
            } else listOf(power)
              steps = listOf(ShortcutStep(address, on, packets))
            }
            beginStep()
        } catch (_: Exception) { finish(false, "Invalid settings or Bluetooth unavailable", abort = true) }
        return START_NOT_STICKY
    }
    private fun beginStep() {
        val step = steps[stepIndex]
        address = step.address; on = step.on; packets = step.packets
        packetIndex = 0; awaitingWrite = false; writeTarget = null
        if (sceneWidgetId != -1) {
            if (sceneWidgetId !in Shortcuts.widgetIds(this) || Shortcuts.widgetPrefs(this, sceneWidgetId).getString("revision", null) != sceneRevision) {
                finish(false, "Widget changed; stopped", abort = true); return
            }
            Shortcuts.sceneStatus(this, sceneWidgetId, sceneRevision, "Sending ${stepIndex + 1}/${steps.size}…")
        }
        try {
            if (sceneWidgetId != -1 && !Shortcuts.savedWidgetTarget(this, address)) { finish(false, "Light removed"); return }
            if(!BluetoothAdapter.checkBluetoothAddress(address)) { finish(false, "Choose a light in the app"); return }
            val adapter = getSystemService(BluetoothManager::class.java).adapter
            if(adapter == null || !adapter.isEnabled) { finish(false, "Bluetooth is off", abort = true); return }
            Shortcuts.report(this, address, "Sending…")
            handler.postDelayed({ finish(false, "No response — open app to retry") }, 15000)
            gatt = adapter.getRemoteDevice(address).connectGatt(this, false, callback, BluetoothDevice.TRANSPORT_LE)
        } catch (_: Exception) { finish(false, "Could not connect — open app to retry") }
    }
    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, state: Int) {
            handler.post {
                if(done || g !== gatt) return@post
                if(status != BluetoothGatt.GATT_SUCCESS || state == BluetoothProfile.STATE_DISCONNECTED) finish(false, "Light disconnected")
                else if(state == BluetoothProfile.STATE_CONNECTED) {
                    try { if(!g.discoverServices()) finish(false, "Service discovery failed") }
                    catch (_: Exception) { finish(false, "Bluetooth unavailable") }
                }
            }
        }
        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            handler.post {
                if(done || g !== gatt) return@post
                if(status != BluetoothGatt.GATT_SUCCESS) { finish(false, "Service discovery failed"); return@post }
                val characteristic = g.getService(UUID.fromString("0000afd0-0000-1000-8000-00805f9b34fb"))
                    ?.getCharacteristic(UUID.fromString("0000afd1-0000-1000-8000-00805f9b34fb"))
                if(characteristic == null) { finish(false, "Unsupported light"); return@post }
                val mode = when {
                    characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0 -> BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                    characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0 -> BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                    else -> { finish(false, "Light is not writable"); return@post }
                }
                writeTarget = characteristic; writeMode = mode
                handler.postDelayed({ if (!done && g === gatt) writeNext() }, 300)
            }
        }
        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            handler.post {
                if (g !== gatt || done || !awaitingWrite || c !== writeTarget) return@post
                awaitingWrite = false
                if (status != BluetoothGatt.GATT_SUCCESS) { finish(false, "Delivery uncertain; not retried"); return@post }
                packetIndex++
                handler.postDelayed({
                    if (g === gatt && !done) {
                        if (packetIndex == packets.size) finish(true, "") else writeNext()
                    }
                }, 150)
            }
        }
    }
    @Suppress("DEPRECATION")
    private fun writeNext() {
        val g = gatt ?: return
        val characteristic = writeTarget ?: return
        if (done || awaitingWrite || packetIndex !in packets.indices) return
        try {
            val bytes = packets[packetIndex]
            awaitingWrite = true
            val accepted = if(Build.VERSION.SDK_INT >= 33) g.writeCharacteristic(characteristic, bytes, writeMode) == BluetoothStatusCodes.SUCCESS
                else { characteristic.writeType = writeMode; characteristic.value = bytes; g.writeCharacteristic(characteristic) }
            if (!accepted) finish(false, "Command not accepted; not retried")
        } catch (_: Exception) { finish(false, "Delivery uncertain; not retried") }
    }
    private fun finish(success: Boolean, error: String, abort: Boolean = false) {
        if(done && owner == null) { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return }
        if(done) return
        handler.removeCallbacksAndMessages(null)
        val closing = gatt
        gatt = null
        try { closing?.disconnect() } catch (_: Exception) { }
        try { closing?.close() } catch (_: Exception) { }
        awaitingWrite = false; writeTarget = null; packets = emptyList()
        if (steps.isNotEmpty()) {
            if (sceneWidgetId != -1) sceneResults.put(org.json.JSONObject().put("address", address)
                .put("status", if (success) "Sent: ${if (on) "On" else "Off"}" else error))
            if(success) { sentCount++; Shortcuts.record(this, address, on) } else Shortcuts.report(this, address, error)
            if (!abort && stepIndex + 1 < steps.size) { stepIndex++; beginStep(); return }
        }
        done = true
        owner?.let { ShortcutLock.release(it) }; owner = null
        if (sceneWidgetId != -1) {
            val summary = if (steps.isEmpty()) error else if (sentCount == steps.size) "Sent: $sentCount lights"
                else "Sent $sentCount/${steps.size}; check lights"
            if (abort) steps.drop(stepIndex + 1).forEach { step ->
                sceneResults.put(org.json.JSONObject().put("address", step.address).put("status", "Not attempted"))
            }
            Shortcuts.sceneStatus(this, sceneWidgetId, sceneRevision, summary, sceneResults.toString())
        } else if (steps.isEmpty()) Shortcuts.report(this, address, error)
        steps = emptyList()
        stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }
    override fun onDestroy() { if(!done) finish(false, "Command interrupted; state unknown", abort = true); super.onDestroy() }
}
