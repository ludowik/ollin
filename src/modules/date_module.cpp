#include "value.h"
#include "module_utils.h"

#include <chrono>
#include <cmath>
#include <ctime>

// The calendar, which time() alone cannot give: it returns seconds since the Unix epoch, and
// turning those into a day and an hour means leap years, month lengths, and above all a TIME ZONE
// with its summer time — none of which a script should have to work out.
//
// date.now([t])  the parts of the LOCAL time; with no argument, of this instant
// date.utc([t])  the same in UTC, which is what makes the decoding testable: an epoch second maps
//                to one and only one answer, whatever the machine's zone.
// date.parse(s)  the parts of a date written "2026-11-01", or nil for a text that is not exactly
//                one: four digits, two and two, and a day its month has. The calendar is worked out
//                here and not through the C library, whose range is the platform's (Windows stops
//                in 3000), so that the same text gives the same answer everywhere.
// date.monthLength(year, month)  the days a month has, February's depending on the year.
//
// The first three return a plain map, like graphics.modelSize: no class, no method, nothing to learn.

static Value parts_of(const std::tm& tm, int millis) {
    // ISO numbering for the weekday, Monday = 1 to Sunday = 7. The C library counts Sunday as 0,
    // which puts the week-end at both ends and trips up every "is it a weekday" test.
    return MapBuilder()
        .int_num("year", tm.tm_year + 1900)
        .int_num("month", tm.tm_mon + 1)        // 1..12
        .int_num("day", tm.tm_mday)             // 1..31
        .int_num("hour", tm.tm_hour)            // 0..23
        .int_num("minute", tm.tm_min)
        .int_num("second", tm.tm_sec)
        .int_num("millisecond", millis)         // 0..999
        .int_num("weekday", tm.tm_wday == 0 ? 7 : tm.tm_wday)
        .int_num("yearDay", tm.tm_yday + 1)     // 1..366
        .done();
}

// The instant to decode, in SECONDS since the epoch — the unit time() returns — as a whole second
// plus the milliseconds left over. The split uses a FLOOR and not a truncation, so a date before
// 1970 keeps its milliseconds in 0..999 instead of going negative.
static void instant(CallCtx& ctx, const char* fn, std::time_t* secs, int* millis) {
    double t;
    if (ctx.argc >= 1) {
        t = num_arg(ctx.args, ctx.argc, 0, fn);
    } else {
        auto now = std::chrono::system_clock::now().time_since_epoch();
        t = std::chrono::duration<double>(now).count();
    }
    double whole = std::floor(t);
    *secs = (std::time_t)whole;
    *millis = (int)((t - whole) * 1000.0);
    if (*millis > 999)      // a fraction of 0.9999 rounds to 1000 in double: keep the field valid
        *millis = 999;
}

static int date_now(CallCtx& ctx) {
    std::time_t t;
    int millis;
    instant(ctx, "date.now", &t, &millis);
    std::tm tm{};
#ifdef _WIN32
    localtime_s(&tm, &t);
#else
    localtime_r(&t, &tm);
#endif
    return ctx.ret(parts_of(tm, millis));
}

static int date_utc(CallCtx& ctx) {
    std::time_t t;
    int millis;
    instant(ctx, "date.utc", &t, &millis);
    std::tm tm{};
#ifdef _WIN32
    gmtime_s(&tm, &t);
#else
    gmtime_r(&t, &tm);
#endif
    return ctx.ret(parts_of(tm, millis));
}

// The Gregorian rule: every fourth year, except the centuries that 400 does not divide.
static bool is_leap_year(long long year) {
    return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}

static int month_length(long long year, int month) {
    static const int days[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return month == 2 && is_leap_year(year) ? 29 : days[month - 1];
}

// Days since 1970-01-01 of a date of the proleptic Gregorian calendar (Hinnant's days_from_civil).
static long long days_from_civil(long long year, int month, int day) {
    year -= month <= 2 ? 1 : 0;
    long long era = (year >= 0 ? year : year - 399) / 400;
    long long year_of_era = year - era * 400;
    long long day_of_year = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
    long long day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    return era * 146097 + day_of_era - 719468;
}

static int date_parse(CallCtx& ctx) {
    const std::string& text = str_arg(ctx.args, ctx.argc, 0, "date.parse");
    if (text.size() != 10 || text[4] != '-' || text[7] != '-')
        return ctx.ret(Value());
    int digits[8];
    const int positions[8] = {0, 1, 2, 3, 5, 6, 8, 9};
    for (int i = 0; i < 8; ++i) {
        char c = text[positions[i]];
        if (c < '0' || c > '9')
            return ctx.ret(Value());
        digits[i] = c - '0';
    }
    int year = digits[0] * 1000 + digits[1] * 100 + digits[2] * 10 + digits[3];
    int month = digits[4] * 10 + digits[5];
    int day = digits[6] * 10 + digits[7];
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > month_length(year, month))
        return ctx.ret(Value());
    long long days = days_from_civil(year, month, day);
    std::tm tm{};
    tm.tm_year = year - 1900;
    tm.tm_mon = month - 1;
    tm.tm_mday = day;
    tm.tm_wday = (int)(((days + 4) % 7 + 7) % 7);   // 1970-01-01 was a Thursday; 0 is Sunday, as in the C library
    tm.tm_yday = (int)(days - days_from_civil(year, 1, 1));
    return ctx.ret(parts_of(tm, 0));
}

static int date_month_length(CallCtx& ctx) {
    double year = num_arg(ctx.args, ctx.argc, 0, "date.monthLength");
    double month = num_arg(ctx.args, ctx.argc, 1, "date.monthLength");
    if (year != std::floor(year) || month != std::floor(month))
        throw std::runtime_error("date.monthLength: expected a whole year and a whole month");
    if (!(std::fabs(year) <= 1e15))
        throw std::runtime_error("date.monthLength: the year is out of range");
    if (month < 1 || month > 12)
        throw std::runtime_error("date.monthLength: the month must be 1 to 12, got " + std::to_string((long long)month));
    return ctx.ret(Value((int64_t)month_length((long long)year, (int)month)));
}

Value make_date_module() {
    return MapBuilder()
        .fn("now", date_now)
        .fn("utc", date_utc)
        .fn("parse", date_parse)
        .fn("monthLength", date_month_length)
        .done();
}
