## Regression tests — The date module.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/date.ol — it must finish without error.

## The `date` module. Only the UTC decoding is testable: it maps one epoch second to one and only
## one answer, whatever the machine's time zone. The local decoding is checked for RANGE alone,
## since its result depends on where the test runs.
var dt_epoch = date.utc(0)
assert(dt_epoch.year == 1970)
assert(dt_epoch.month == 1)
assert(dt_epoch.day == 1)
assert(dt_epoch.hour == 0)
assert(dt_epoch.minute == 0)
assert(dt_epoch.second == 0)
assert(dt_epoch.weekday == 4)     ## a Thursday, in the ISO numbering Monday = 1
assert(dt_epoch.yearDay == 1)

## A leap year, at the end of a day: 2024-02-29 23:59:59 UTC = 1709251199. The day after February
## the 28th only exists in a leap year, so a naive calendar gets this one wrong.
var dt_leap = date.utc(1709251199)
assert(dt_leap.year == 2024)
assert(dt_leap.month == 2)
assert(dt_leap.day == 29)
assert(dt_leap.hour == 23)
assert(dt_leap.minute == 59)
assert(dt_leap.second == 59)
assert(dt_leap.weekday == 4)
assert(dt_leap.yearDay == 60)     ## 31 + 29

## The fraction of a second becomes the MILLISECONDS; the second itself is not rounded up.
assert(date.utc(1709251199.99).second == 59)
assert(date.utc(1709251199.99).millisecond == 990)
assert(date.utc(1709251199).millisecond == 0)
assert(date.utc(1709251199.25).millisecond == 250)

## Before 1970 the epoch time is NEGATIVE. The split takes the floor, so the milliseconds stay in
## 0..999 and the second is the one that CONTAINS the instant: -0.25 s is 23:59:59.750 of 1969.
var dt_before = date.utc(-0.25)
assert(dt_before.year == 1969)
assert(dt_before.hour == 23)
assert(dt_before.minute == 59)
assert(dt_before.second == 59)
assert(dt_before.millisecond == 750)

var dt_now = date.now()
assert(dt_now.year >= 2024)
assert(dt_now.month >= 1 and dt_now.month <= 12)
assert(dt_now.day >= 1 and dt_now.day <= 31)
assert(dt_now.hour >= 0 and dt_now.hour <= 23)
assert(dt_now.minute >= 0 and dt_now.minute <= 59)
assert(dt_now.second >= 0 and dt_now.second <= 60)   ## 60 exists: a leap second
assert(dt_now.millisecond >= 0 and dt_now.millisecond <= 999)
assert(dt_now.weekday >= 1 and dt_now.weekday <= 7)
assert(dt_now.yearDay >= 1 and dt_now.yearDay <= 366)

## date.parse reads a date written "2026-11-01" and gives the same parts as date.utc, with the time at zero.
var dt_parsed = date.parse("2026-11-01")
assert(dt_parsed.year == 2026 and dt_parsed.month == 11 and dt_parsed.day == 1)
assert(dt_parsed.hour == 0 and dt_parsed.minute == 0 and dt_parsed.second == 0 and dt_parsed.millisecond == 0)
assert(dt_parsed.weekday == 7, "a Sunday, in the ISO numbering")
assert(dt_parsed.yearDay == 305)
assert(date.parse("1970-01-01").weekday == 4 and date.parse("1970-01-01").yearDay == 1)
assert(date.parse("2024-02-29").weekday == 4 and date.parse("2024-02-29").yearDay == 60, "a leap day")
assert(date.parse("0001-01-01").weekday == 1 and date.parse("9999-12-31").weekday == 5, "the ends of the range")
assert(date.parse("9999-12-31").yearDay == 365)

## date.utc and date.parse share one calendar, so the checks that matter are against dates known independently of
## it: instants worked out with another implementation (Python's datetime), at the edges where a calendar goes
## wrong — the ends of the range, a century that is not a leap year and one that is, the day before and after.
## [instant, year, month, day, hour, minute, second, ISO weekday, year day]
var dt_known = [
    [-62135596800, 1, 1, 1, 0, 0, 0, 1, 1], [-11644473600, 1601, 1, 1, 0, 0, 0, 1, 1],
    [-2208988800, 1900, 1, 1, 0, 0, 0, 1, 1], [-2203891201, 1900, 2, 28, 23, 59, 59, 3, 59],
    [-2203891200, 1900, 3, 1, 0, 0, 0, 4, 60], [-1, 1969, 12, 31, 23, 59, 59, 3, 365],
    [951782400, 2000, 2, 29, 0, 0, 0, 2, 60], [951827696, 2000, 2, 29, 12, 34, 56, 2, 60],
    [1709251199, 2024, 2, 29, 23, 59, 59, 4, 60], [1767225599, 2025, 12, 31, 23, 59, 59, 3, 365],
    [4107542399, 2100, 2, 28, 23, 59, 59, 7, 59], [4107542400, 2100, 3, 1, 0, 0, 0, 1, 60],
    [253402300799, 9999, 12, 31, 23, 59, 59, 5, 365],
    [253402300800, 10000, 1, 1, 0, 0, 0, 6, 1]]
var dt_fields = ["year", "month", "day", "hour", "minute", "second", "weekday", "yearDay"]
for dt_row in dt_known do
    var dt_got = date.utc(dt_row[1])
    for dt_i = 1, 8 do
        var dt_name = dt_fields[dt_i]
        assert(dt_got[dt_name] == dt_row[dt_i + 1], "date.utc({dt_row[1]}), {dt_name}: {dt_got[dt_name]} instead of {dt_row[dt_i + 1]}")
    end
end

## Reading a decoded day back gives the same day: parse and utc are inverse of each other, whatever the calendar
## rules they share. Every day from 1900 to 2200, then one in 37 across the whole range of years 1 to 9999.
func dtRoundTrip(day)
    var from = date.utc(day * 86400)
    var text = "{from.year:04d}-{from.month:02d}-{from.day:02d}"
    var back = date.parse(text)
    assert(back <> nil, "a real date was refused: " + text)
    assert(back.year == from.year and back.month == from.month and back.day == from.day, text)
    assert(back.weekday == from.weekday and back.yearDay == from.yearDay, "weekday or year day of " + text)
end
for dt_day = -25567, 83984 do
    dtRoundTrip(dt_day)
end
for dt_day = -719162, 2932896, 37 do
    dtRoundTrip(dt_day)
end

## What is no date gives nil: the shape, the characters, and a day the month does not have.
for dt_bad in ["2026-13-01", "2026-00-10", "2026-11-00", "2026-11-31", "2026-04-31", "2026-02-29", "1900-02-29", "2100-02-29",
               "0000-01-01", "2026/11/01", "2026-11-1", "2026-11-01-", "2026-11", "", "26-11-01", "2026-1.-01", "20x6-11-01",
               " 026-11-01", "0x1F-01-01", "1e03-01-01", "+026-01-01", "-026-01-01", "2026-11-01 ", "٢٠٢٦-11-01"] do
    assert(date.parse(dt_bad) == nil, "not a date: " + dt_bad)
end
assert(date.parse("2000-02-29") <> nil and date.parse("2096-02-29") <> nil, "leap days that are real")

## date.monthLength: the months, and February by the Gregorian rule.
var dt_lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
for dt_m = 1, 12 do
    assert(date.monthLength(2026, dt_m) == dt_lengths[dt_m], "month " + dt_m)
end
assert(date.monthLength(2024, 2) == 29 and date.monthLength(2000, 2) == 29, "every fourth year, and the 400")
assert(date.monthLength(1900, 2) == 28 and date.monthLength(2100, 2) == 28, "a century that 400 does not divide")
assert(date.monthLength(2024, 1) == 31 and date.monthLength(2024, 12) == 31, "only February depends on the year")
assert(date.monthLength(-4, 2) == 29 and date.monthLength(0, 2) == 29, "the rule goes on before year 1")
assert(date.monthLength(2026.0, 2.0) == 28, "a whole number written with a point is whole")

## date.weekdayName: the 7 days in each language and each form, numbered as the `weekday` field is (Monday = 1).
var dt_names = {
    en: {long: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
         short: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]},
    fr: {long: ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"],
         short: ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."]}
}
for dt_lang in ["en", "fr"] do
    for dt_form in ["long", "short"] do
        for dt_n = 1, 7 do
            assert(date.weekdayName(dt_n, dt_lang, dt_form) == dt_names[dt_lang][dt_form][dt_n], "{dt_lang} {dt_form} {dt_n}")
        end
    end
end
assert(date.weekdayName(1) == "Monday" and date.weekdayName(7) == "Sunday", "English and long by default")
assert(date.weekdayName(3, "fr") == "mercredi" and date.weekdayName(3, "en", "short") == "Wed", "a language alone, a form after it")
assert(date.weekdayName(date.parse("2026-11-01").weekday, "fr") == "dimanche", "the number a date gives is the one the names take")
assert(date.weekdayName(date.utc(0).weekday, "en") == "Thursday", "1970-01-01 was a Thursday")
assert(date.weekdayName(2.0) == "Tuesday", "a whole number written with a point is whole")

## date.monthName: the 12 months in each language and each form, January being 1 as the `month` field has it.
var dt_months = {
    en: {long: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                "November", "December"],
         short: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]},
    fr: {long: ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre",
                "novembre", "décembre"],
         short: ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]}
}
for dt_lang in ["en", "fr"] do
    for dt_form in ["long", "short"] do
        for dt_n = 1, 12 do
            assert(date.monthName(dt_n, dt_lang, dt_form) == dt_months[dt_lang][dt_form][dt_n], "{dt_lang} {dt_form} {dt_n}")
        end
    end
end
assert(date.monthName(1) == "January" and date.monthName(12) == "December", "English and long by default")
assert(date.monthName(8, "fr") == "août" and date.monthName(2, "en", "short") == "Feb", "a language alone, a form after it")
assert(date.monthName(date.parse("2026-11-01").month, "fr") == "novembre", "the number a date gives is the one the names take")
assert(date.monthName(date.utc(0).month) == "January", "the epoch is in January")
assert(date.monthName(12.0) == "December", "a whole number written with a point is whole")
assert(len(date.monthName(2, "fr")) == 7, "the accent is one character, not two bytes")

