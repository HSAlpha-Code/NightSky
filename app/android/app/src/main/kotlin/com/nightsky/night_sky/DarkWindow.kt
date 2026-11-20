package com.nightsky.night_sky

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.*

/** Astronomical darkness at the selected coordinates. All searches run on the UTC timeline. */
object DarkWindow {
    private const val minute = 60_000L
    private const val day = 1440 * minute
    private const val j2000 = 946728000000L
    private const val threshold = -18.0

    // US Naval Observatory, "Computing Approximate Solar Coordinates". The equation of
    // time converts mean solar time to the apparent solar hour angle at this longitude.
    private fun solarAltitude(time: Long, lat: Double, lon: Double): Double {
        val days = (time - j2000).toDouble() / day
        val anomaly = Math.toRadians((357.529 + 0.98560028 * days) % 360)
        val meanLon = (280.459 + 0.98564736 * days) % 360
        val ecliptic = Math.toRadians(meanLon + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly))
        val obliquity = Math.toRadians(23.439 - 0.00000036 * days)
        val ra = Math.toDegrees(atan2(cos(obliquity) * sin(ecliptic), cos(ecliptic)))
        val dec = asin(sin(obliquity) * sin(ecliptic))
        val hourAngle = Math.toRadians((time % day) * 360.0 / day - 180 + lon + meanLon - ra)
        val latitude = Math.toRadians(lat)
        val sine = sin(latitude) * sin(dec) + cos(latitude) * cos(dec) * cos(hourAngle)
        return Math.toDegrees(asin(sine.coerceIn(-1.0, 1.0)))
    }

    fun describe(now: Long, lat: Double, lon: Double): String {
        if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return "Choose a location in Sky View"
        // Limit this observing forecast to 2000–2050 inclusive.
        if (now !in 946684800000L until 2556144000000L) return "Available for 2000–2050"
        val format = SimpleDateFormat("MMM d HH:mm z", Locale.getDefault())
        fun display(time: Long) = format.format(Date(((time + minute / 2) / minute) * minute))

        val initial = solarAltitude(now, lat, lon)
        val alreadyDark = initial < threshold
        var start: Long? = if (alreadyDark) now else null
        var minAltitude = initial
        var maxAltitude = initial
        var previous = now
        var wasDark = alreadyDark
        // Find a start within 24 hours, then follow that window for up to another day.
        while (previous < (start ?: now) + day) {
            val next = minOf(previous + 5 * minute, (start ?: now) + day)
            val altitude = solarAltitude(next, lat, lon)
            minAltitude = min(minAltitude, altitude)
            maxAltitude = max(maxAltitude, altitude)
            val isDark = altitude < threshold
            if (isDark != wasDark) {
                var low = previous
                var high = next
                while (high - low > 1_000L) {
                    val mid = (low + high) / 2
                    if ((solarAltitude(mid, lat, lon) < threshold) == wasDark) low = mid else high = mid
                }
                if (!isDark) {
                    val from = if (alreadyDark) "Now" else display(requireNotNull(start))
                    return "$from – ${display(high)} (approx.)"
                }
                start = high
                maxAltitude = altitude
            }
            previous = next
            wasDark = isDark
        }
        // Avoid categorically predicting a polar day/night at a grazing threshold. The
        // guard exceeds the solar model error and a missed extremum between samples.
        return when {
            start == null && minAltitude > threshold + 0.05 -> "No astronomical darkness in the next 24 h"
            start == null || maxAltitude > threshold - 0.05 -> "Near twilight limit • timing uncertain"
            alreadyDark -> "Astronomical darkness for the next 24 h"
            else -> "From ${display(start)} for at least 24 h (approx.)"
        }
    }
}
