package com.nightsky.night_sky

import java.time.Instant
import java.util.Locale
import java.util.TimeZone

fun main() {
    Locale.setDefault(Locale.US)
    TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
    // Spring forward. A single elapsed hour crosses two local clock hours.
    val utc = Instant.parse("2026-03-08T07:30:00Z").toEpochMilli()
    val moon = ObservingEvent("full", "Full Moon", utc, "full")
    check(localStamp(utc - HOUR).contains("1:30"))
    check(localStamp(utc).contains("3:30"))
    check(moon.trigger(utc - 2 * HOUR, false) == utc - HOUR)
    check(moon.trigger(utc - HOUR / 2, false) == null)
    check(moon.trigger(utc - HOUR / 2, true) == utc - HOUR / 2)
    check(moon.trigger(utc, true) == null)

    val shower = ObservingEvent("shower", "Meteor maximum", utc + HOUR, "shower")
    val quarter = ObservingEvent("quarter", "Last Quarter", utc + 168 * HOUR, "last")
    val events = listOf(moon, shower, quarter)
    check(calendarWidgetText(events, utc, true).startsWith("Full Moon"))
    check(calendarWidgetText(events, utc + 60_000, true).startsWith("Waning gibbous"))
    check(calendarWidgetText(events, utc, false).startsWith("Meteor maximum\nApprox."))
    check(calendarWidgetText(events, utc + HOUR, false).startsWith("Last Quarter"))
    check(calendarWidgetText(events, quarter.utc + HOUR, false) == "Outside bundled calendar")
}
