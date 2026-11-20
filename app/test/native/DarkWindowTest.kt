package com.nightsky.night_sky

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs

/** Offline reference cases. Run on the JVM alongside DarkWindow.kt. */
fun main() {
    TimeZone.setDefault(TimeZone.getTimeZone("Europe/London"))
    Locale.setDefault(Locale.UK)
    fun forecast(utc: String, lat: Double, lon: Double) =
        DarkWindow.describe(Instant.parse(utc).toEpochMilli(), lat, lon)

    // https://www.timeanddate.com/sun/uk/london?month=3&year=2026
    // Check both endpoints in elapsed time, including the spring-forward night.
    fun checkLondon(now: String, expectedStart: String, expectedEnd: String) {
        val formatted = forecast(now, 51.508, -0.128)
        val endpoints = formatted.removeSuffix(" (approx.)").split(" – ")
        check(endpoints.size == 2) { formatted }
        val format = DateTimeFormatter.ofPattern("yyyy MMM d HH:mm", Locale.UK)
        for ((endpoint, expected) in endpoints.zip(listOf(expectedStart, expectedEnd))) {
            val local = LocalDateTime.parse("2026 " + endpoint.substringBeforeLast(' '), format)
            val actual = local.atZone(ZoneId.of("Europe/London"))
            check(endpoint.endsWith(actual.format(DateTimeFormatter.ofPattern("z", Locale.UK))))
            check(abs(ChronoUnit.SECONDS.between(Instant.parse(expected), actual.toInstant())) <= 120) {
                "$formatted differs from $expected"
            }
        }
    }
    checkLondon("2026-03-20T12:00:00Z", "2026-03-20T20:07:00Z", "2026-03-21T04:07:00Z")
    checkLondon("2026-03-28T12:00:00Z", "2026-03-28T20:23:00Z", "2026-03-29T03:46:00Z")
    check(forecast("2026-03-20T23:00:00Z", 51.508, -0.128).startsWith("Now – "))
    // https://www.timeanddate.com/sun/norway/longyearbyen?month=6&year=2026
    // https://www.timeanddate.com/sun/antarctica/south-pole?month=6&year=2026
    check(forecast("2026-06-21T12:00:00Z", 78.22, 15.65).startsWith("No astronomical darkness"))
    check(forecast("2026-06-21T12:00:00Z", -90.0, 0.0).startsWith("Astronomical darkness for"))
    check(forecast("2051-01-01T00:00:00Z", 0.0, 0.0).startsWith("Available for"))
    check(forecast("2026-03-20T12:00:00Z", Double.NaN, 0.0).startsWith("Choose a location"))
}
