package dev.kslight.ks_light

import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.service.controls.Control
import android.service.controls.ControlsProviderService
import android.service.controls.DeviceTypes
import android.service.controls.actions.BooleanAction
import android.service.controls.actions.ControlAction
import android.service.controls.templates.ControlButton
import android.service.controls.templates.ToggleTemplate
import java.util.concurrent.Flow
import java.util.function.Consumer

/** Android 11+ system controls. IDs include the target so old favorites cannot control a new lamp. */
class LightDeviceControls : ControlsProviderService() {
    private val handler = Handler(Looper.getMainLooper())
    private val subscriptions = mutableSetOf<LightSubscription>()
    private fun targetId(): String? = if (Shortcuts.configured(this))
        "power:" + Shortcuts.prefs(this).getString("address", "") else null

    private fun control(id: String, stateless: Boolean): Control {
        val p = Shortcuts.prefs(this)
        val valid = id == targetId()
        val rawName = p.getString("name", "KS Light") ?: "KS Light"
        val name = if (rawName.startsWith("KS03~")) "KS Light" else rawName
        if (stateless) return Control.StatelessBuilder(id, Shortcuts.activity(this))
            .setTitle(name).setSubtitle("Bluetooth light").setDeviceType(DeviceTypes.TYPE_LIGHT)
            .setStructure("KS Light").build()
        val on = valid && p.getBoolean("last_on", false)
        val status = if (!valid) "Choose this light again in the app" else
            p.getString("status", "State unknown") ?: "State unknown"
        return Control.StatefulBuilder(id, Shortcuts.activity(this))
            .setTitle(if (valid) name else "Light removed").setSubtitle("Last sent state")
            .setDeviceType(DeviceTypes.TYPE_LIGHT).setStructure("KS Light")
            .setStatus(if (valid) Control.STATUS_OK else Control.STATUS_NOT_FOUND)
            .setStatusText(status)
            .setControlTemplate(ToggleTemplate(id, ControlButton(on, "Power"))).build()
    }

    override fun createPublisherForAllAvailable(): Flow.Publisher<Control> = publisher(null)
    override fun createPublisherFor(controlIds: MutableList<String>): Flow.Publisher<Control> =
        publisher(controlIds.toList())

    private fun publisher(ids: List<String>?): Flow.Publisher<Control> = Flow.Publisher { subscriber ->
        handler.post {
            val targets = if (ids == null) listOfNotNull(targetId()) else ids.distinct()
            val subscription = LightSubscription(subscriber, targets, ids == null)
            subscriptions.add(subscription)
            if (ids != null) Shortcuts.prefs(this).registerOnSharedPreferenceChangeListener(subscription)
            subscriber.onSubscribe(subscription)
            if (targets.isEmpty()) subscription.complete()
        }
    }

    // A single latest snapshot is retained when the system has no demand; updates never queue indefinitely.
    private inner class LightSubscription(
        val subscriber: Flow.Subscriber<in Control>, val ids: List<String>, val once: Boolean
    ) : Flow.Subscription, SharedPreferences.OnSharedPreferenceChangeListener {
        var demand = 0L
        val pending = ids.toMutableSet()
        var cancelled = false
        override fun request(n: Long) { handler.post {
            if (!cancelled) {
                if (n <= 0) { cancelNow(); subscriber.onError(IllegalArgumentException("Positive demand required")) }
                else { demand = if (Long.MAX_VALUE - demand < n) Long.MAX_VALUE else demand + n; emit() }
            }
        } }
        override fun cancel() { handler.post { cancelNow() } }
        fun cancelNow() {
            cancelled = true
            Shortcuts.prefs(this@LightDeviceControls).unregisterOnSharedPreferenceChangeListener(this)
            subscriptions.remove(this)
        }
        fun complete() { if (!cancelled) { cancelNow(); subscriber.onComplete() } }
        override fun onSharedPreferenceChanged(p: SharedPreferences, key: String?) {
            handler.post { pending.addAll(ids); emit() }
        }
        private fun emit() {
            while (!cancelled && demand > 0 && pending.isNotEmpty()) {
                val id = pending.first()
                pending.remove(id); demand--
                subscriber.onNext(control(id, once))
            }
            if (once && pending.isEmpty()) complete()
        }
    }

    override fun performControlAction(id: String, action: ControlAction, consumer: Consumer<Int>) {
        handler.post {
            if (id != targetId() || action !is BooleanAction || action.templateId != id) {
                consumer.accept(ControlAction.RESPONSE_FAIL)
            } else try {
                val intent = android.content.Intent(this, ShortcutPowerService::class.java)
                    .putExtra("on", action.newState).putExtra("expected_address", id.removePrefix("power:"))
                startForegroundService(intent)
                // Acknowledges dispatch; the subscription reports actual write completion or error.
                consumer.accept(ControlAction.RESPONSE_OK)
            } catch (_: Exception) {
                Shortcuts.update(this, "Open app to retry")
                consumer.accept(ControlAction.RESPONSE_FAIL)
            }
        }
    }
    override fun onDestroy() {
        subscriptions.toList().forEach { it.complete() }
        super.onDestroy()
    }
}
