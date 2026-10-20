## Regression tests — The date module.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/date.ol — it must finish without error.

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
