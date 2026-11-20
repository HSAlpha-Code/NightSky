package com.nightsky.night_sky

import java.text.DateFormat
import java.util.Date

internal const val HOUR = 3_600_000L
internal data class ObservingEvent(val id: String, val title: String, val utc: Long, val kind: String) {
    // An opted-in alarm may catch up after reboot, until its event expires.
    fun trigger(now: Long, restoring: Boolean): Long? = when {
        utc <= now -> null
        utc - HOUR > now -> utc - HOUR
        restoring -> now
        else -> null
    }
}

internal fun localStamp(time: Long): String =
    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(time))

internal fun calendarWidgetText(events: List<ObservingEvent>, now: Long, moon: Boolean): String {
    val next = events.firstOrNull { it.utc > now && (!moon || it.kind != "shower") }
    if (next == null || now < events.first().utc) return "Outside bundled calendar"
    if (!moon) {
        val prefix = if (next.kind == "shower") "Approx. " else ""
        return "${next.title}\n$prefix${localStamp(next.utc)}"
    }
    val previous = events.lastOrNull { it.kind != "shower" && it.utc <= now }
        ?: return "Outside bundled lunar calendar"
    val phase = when {
        now - previous.utc < 60_000L -> previous.title
        next.kind == "first" -> "Waxing crescent"
        next.kind == "full" -> "Waxing gibbous"
        next.kind == "last" -> "Waning gibbous"
        else -> "Waning crescent"
    }
    return "$phase\nNext: ${next.title} · ${localStamp(next.utc)}"
}
