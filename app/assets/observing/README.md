# Offline observing calendar

`events.csv` contains 297 primary lunar phases for calendar years 2025 through 2030 and eight meteor shower peak estimates for 2026 and 2027. All times apply worldwide. Terrain, cloud, daylight, moonlight and a shower's radiant altitude affect what an observer sees.

## Sources and reuse

The four lunar phase times come from the U.S. Naval Observatory Astronomical Applications Department, API v4.0.1, at its published one-minute resolution. USNO supplies computed astronomical facts for general use and explicitly supports embedding its API results in applications. U.S. federal government works are public domain in the United States. [API documentation](https://aa.usno.navy.mil/data/api) · [USNO use of astronomical data](https://aa.usno.navy.mil/faq/lawyers)

The meteor records use individual factual estimates from the International Meteor Organization's annual calendars, edited by Jürgen Rendtel. The selection includes the Quadrantids, Perseids, Leonids and Geminids. The timestamp is the nominal time of maximum, or, for the Perseids, the midpoint of the published two-hour interval. A peak may be broad or shift by hours. The calendar describes the regular shower maximum and omits separate dust-trail encounters. The original publications retain their copyright. This independently assembled CSV uses only names and numeric facts. [2026 calendar](https://www.imo.net/files/meteor-shower/cal2026.pdf) · [2027 calendar](https://www.imo.net/files/meteor-shower/cal2027.pdf) · [U.S. Copyright Office guidance on facts](https://www.copyright.gov/help/faq/faq-protect.html)

## Updating the bundle

1. For each additional year, fetch the [USNO annual phase JSON](https://aa.usno.navy.mil/api/moon/phases/year?year=2030), changing the year parameter. Check that the number of phase records matches `numphases` and each row belongs to the requested year. Combine the supplied year, month, day and Universal Time with a UTC offset of zero. At one-minute precision the UT1/UTC difference is negligible.
2. Review the individual shower sections of the corresponding IMO annual calendar. Enter that year's nominal peak with an explicit UTC offset, taking the midpoint if a range is published. Omit showers for which only a date is available until the format supports date-only estimates.
3. Use the header `id,title,utcMillis,kind`. Store integer Unix milliseconds and a kind of `new`, `first`, `full`, `last` or `shower`. Lunar IDs use `moon-<kind>-YYYYMMDD` and shower IDs use the lowercase shower name plus `-YYYY`. Preserve existing IDs if source times are revised, including a revision over midnight.
4. Sort all rows by ascending instant, check for duplicate IDs and verify the four-phase cycle. Update the coverage in this document and the app when extending the bundle. Distribute the revised asset in an app update.
