package dev.kslight.ks_light

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.widget.*
import org.json.JSONObject

/** Native launcher setup: configure a widget without changing the app/tile target. */
class WidgetSetupActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        if (AppWidgetManager.getInstance(this).getAppWidgetInfo(id)?.provider != ComponentName(this, LightWidget::class.java)) { finish(); return }
        val spacing = (20 * resources.displayMetrics.density).toInt()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(spacing, spacing, spacing, spacing)
            setOnApplyWindowInsetsListener { view, insets ->
                if (android.os.Build.VERSION.SDK_INT >= 30) {
                    val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars() or android.view.WindowInsets.Type.displayCutout())
                    view.setPadding(spacing + bars.left, spacing + bars.top, spacing + bars.right, spacing + bars.bottom)
                } else {
                    @Suppress("DEPRECATION")
                    view.setPadding(spacing + insets.systemWindowInsetLeft, spacing + insets.systemWindowInsetTop,
                        spacing + insets.systemWindowInsetRight, spacing + insets.systemWindowInsetBottom)
                }
                insets
            }
        }
        layout.addView(TextView(this).apply { text = "Choose widget controls"; textSize = 24f })
        layout.addView(TextView(this).apply { text = "Choose a light's power controls, favorite color, or a saved scene below. Scenes support up to 8 KS03 lights. Tap the widget name later to change it."; setPadding(0, 16, 0, 24) })
        val preferences = getSharedPreferences("light_settings", MODE_PRIVATE)
        val lights = try { JSONObject(preferences.getString("library_real", "{}") ?: "{}").optJSONObject("lights") ?: JSONObject() } catch (_: Exception) { JSONObject() }
        val settings = try { JSONObject(preferences.getString("devices", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
        var count = 0
        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val priorResults = try { org.json.JSONArray(Shortcuts.widgetPrefs(this, id).getString("scene_results", "[]")) } catch (_: Exception) { org.json.JSONArray() }
        if (priorResults.length() > 0) {
            list.addView(TextView(this).apply { text = "Last scene results"; textSize = 20f })
            for (index in 0 until priorResults.length()) {
                val item = priorResults.optJSONObject(index) ?: continue
                val address = item.optString("address")
                val custom = settings.optJSONObject(address)?.optString("name", "") ?: ""
                val name = if (custom.isNotBlank()) custom else lights.optJSONObject(address)?.optString("name", "Light") ?: "Removed light"
                list.addView(TextView(this).apply { text = "$name: ${item.optString("status")}"; setPadding(0, 8, 0, 8) })
            }
        }
        for (address in lights.keys()) {
            val light = lights.optJSONObject(address) ?: continue
            if (light.optString("prefix") != "KS03~" || !android.bluetooth.BluetoothAdapter.checkBluetoothAddress(address)) continue
            val custom = settings.optJSONObject(address)?.optString("name", "") ?: ""
            val name = if (custom.isNotBlank()) custom else light.optString("name", "KS Light")
            count++
            list.addView(Button(this).apply {
                text = "$name\n$address"
                setOnClickListener {
                    val favorite = Shortcuts.lastColor(this@WidgetSetupActivity, address)
                    val choices = if (favorite == null) arrayOf("On / Off") else arrayOf(
                        "On / Off", "Favorite ${favorite.hex} · ${kotlin.math.round(favorite.brightness * 100.0 / 255).toInt()}% / Off")
                    AlertDialog.Builder(this@WidgetSetupActivity)
                        .setTitle(if (favorite == null) "Apply a color in the app to enable favorites" else "Choose widget controls")
                        .setItems(choices) { _, choice -> saveWidget(id, address, name, if (choice == 1) favorite else null) }
                        .setNegativeButton("Cancel", null).show()
                }
            })
        }
        if (count == 0) layout.addView(TextView(this).apply { text = "No saved KS03 lights. Open KS Light and use Add devices first." })
        val scenes = WidgetScene.available(this)
        if (scenes.isNotEmpty()) {
            list.addView(TextView(this).apply { text = "Saved scenes"; textSize = 20f; setPadding(0, 24, 0, 8) })
            list.addView(TextView(this).apply { text = "Scene widgets keep a snapshot of up to 8 KS03 lights. Tap the widget name to replace it after editing a scene." })
            for (scene in scenes) list.addView(Button(this).apply {
                text = "${scene.name} · ${scene.members.size} lights"
                setOnClickListener {
                    if (!Shortcuts.assignScene(this@WidgetSetupActivity, id, scene)) {
                        Toast.makeText(this@WidgetSetupActivity, "Could not save scene widget. Reopen setup to try again.", Toast.LENGTH_LONG).show()
                    } else {
                        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
                        finish()
                    }
                }
            })
        }
        layout.addView(ScrollView(this).apply { addView(list) }, LinearLayout.LayoutParams(-1, 0, 1f))
        layout.addView(Button(this).apply { text = "Cancel"; setOnClickListener { finish() } })
        setContentView(layout)
    }

    private fun saveWidget(id: Int, address: String, name: String, favorite: FavoriteColor?) {
        if (!Shortcuts.assignWidget(this, id, address, name, favorite)) {
            Toast.makeText(this, "Could not save. The light or widget may have been removed. Reopen setup to try again.", Toast.LENGTH_LONG).show()
            return
        }
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
        finish()
    }
}
