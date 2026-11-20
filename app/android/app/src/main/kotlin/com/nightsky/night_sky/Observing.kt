package com.nightsky.night_sky

import android.app.*
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.*
import android.os.Build
import android.widget.RemoteViews
import org.json.JSONObject

private const val CHANNEL = "observing_reminders"
private const val ALARM = "com.nightsky.night_sky.OBSERVING_ALARM"
private const val IMMUTABLE = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

internal object Observing {
    private var calendar: List<ObservingEvent>? = null
    fun events(context: Context): List<ObservingEvent> = calendar ?: context.assets
        .open("flutter_assets/assets/observing/events.csv").bufferedReader().useLines { lines ->
            lines.drop(1).filter { it.isNotBlank() }.map { line ->
                val (id, title, millis, kind) = line.split(',')
                ObservingEvent(id, title, millis.toLong(), kind)
            }.sortedBy { it.utc }.toList()
        }.also { calendar = it }

    private fun prefs(c: Context) = c.getSharedPreferences("observing_reminders", Context.MODE_PRIVATE)
    private fun manager(c: Context) = c.getSystemService(NotificationManager::class.java)
    fun permitted(c: Context): Boolean {
        val nm = manager(c)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Observing reminders", NotificationManager.IMPORTANCE_DEFAULT))
            if (nm.getNotificationChannel(CHANNEL).importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        return nm.areNotificationsEnabled()
    }

    private fun alarm(c: Context, id: String): PendingIntent {
        val intent = Intent(c, ObservingReceiver::class.java).setAction(ALARM).addCategory(id)
        return PendingIntent.getBroadcast(c, 0, intent, IMMUTABLE)
    }

    fun destination(c: Context, page: String): PendingIntent {
        val intent = Intent(c, MainActivity::class.java).setAction("night_sky.open.$page")
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(c, 0, intent, IMMUTABLE)
    }

    fun status(c: Context, id: String): String {
        if (prefs(c).contains(id)) {
            val event = events(c).find { it.id == id }
            if (event == null || event.utc <= System.currentTimeMillis()) cancel(c, id)
            else return if (permitted(c)) "scheduled" else "paused"
        }
        return if (permitted(c)) "off" else "blocked"
    }

    fun schedule(c: Context, event: ObservingEvent, restoring: Boolean = false): Boolean {
        val now = System.currentTimeMillis()
        val trigger = event.trigger(now, restoring) ?: return false
        if (!restoring && !permitted(c)) return false
        val alarms = c.getSystemService(AlarmManager::class.java)
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, alarm(c, event.id))
        prefs(c).edit().putBoolean(event.id, true).apply()
        return true
    }

    fun cancel(c: Context, id: String) {
        prefs(c).edit().remove(id).apply()
        c.getSystemService(AlarmManager::class.java).cancel(alarm(c, id))
        manager(c).cancel(id, 1)
    }

    fun restore(c: Context) {
        if (prefs(c).all.isEmpty()) return
        val byId = events(c).associateBy { it.id }
        for (id in prefs(c).all.keys) {
            val event = byId[id]
            if (event == null || !schedule(c, event, restoring = true)) cancel(c, id)
        }
    }

    fun deliver(c: Context, id: String) {
        if (!prefs(c).contains(id)) return
        val event = events(c).find { it.id == id }
        val now = System.currentTimeMillis()
        if (event == null || now >= event.utc) { cancel(c, id); return }
        if (now < event.utc - HOUR) { schedule(c, event, restoring = true); return }
        if (!permitted(c)) return
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, CHANNEL) else Notification.Builder(c)
        val message = (if (event.kind == "shower") "Approximate peak " else "Global phase ") + localStamp(event.utc)
        manager(c).notify(id, 1, builder.setSmallIcon(R.drawable.ic_observing)
            .setContentTitle(event.title).setContentText(message)
            .setContentIntent(destination(c, "events")).setAutoCancel(true).build())
        prefs(c).edit().remove(id).apply()
    }

    fun refresh(c: Context) {
        val wm = AppWidgetManager.getInstance(c)
        for (provider in listOf(MoonWidget::class.java, EventWidget::class.java, DarknessWidget::class.java)) {
            val ids = wm.getAppWidgetIds(ComponentName(c, provider))
            if (ids.isNotEmpty()) update(c, provider, ids)
        }
    }

    fun update(c: Context, provider: Class<*>, ids: IntArray) {
        val now = System.currentTimeMillis()
        val settings = JSONObject(c.getSharedPreferences("night_sky", Context.MODE_PRIVATE).getString("settings", null) ?: "{}")
        val moon = provider == MoonWidget::class.java
        val dark = provider == DarknessWidget::class.java
        val title = if (dark) "Astronomical darkness" else if (moon) "Moon phase" else "Next observing event"
        val text = if (dark) {
            val lat = settings.optDouble("manualLatitude")
            val lon = settings.optDouble("manualLongitude")
            if (!lat.isFinite() || !lon.isFinite()) "Set a location in Sky View"
            else DarkWindow.describe(now, lat, lon)
        } else {
            calendarWidgetText(events(c), now, moon)
        }
        val view = RemoteViews(c.packageName, R.layout.observing_widget)
        view.setTextViewText(R.id.widget_title, title)
        view.setTextViewText(R.id.widget_text, text)
        if (settings.optBoolean("nightVision")) {
            for (id in listOf(R.id.widget_title, R.id.widget_text)) view.setTextColor(id, 0xffff6666.toInt())
        } else {
            view.setTextColor(R.id.widget_title, 0xffbcc6ff.toInt())
            view.setTextColor(R.id.widget_text, android.graphics.Color.WHITE)
        }
        view.setOnClickPendingIntent(R.id.widget_root, destination(c, if (dark) "sky" else if (moon) "moon" else "events"))
        AppWidgetManager.getInstance(c).updateAppWidget(ids, view)
    }
}

open class ObservingWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        Observing.update(context, javaClass, ids)
}
class MoonWidget : ObservingWidget()
class EventWidget : ObservingWidget()
class DarknessWidget : ObservingWidget()

class ObservingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ALARM) intent.categories?.singleOrNull()?.let { Observing.deliver(context, it) }
        else {
            Observing.restore(context)
            Observing.refresh(context)
        }
    }
}
