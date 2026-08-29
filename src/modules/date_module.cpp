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
//
// Both return a plain map, like graphics.modelSize: no class, no method, nothing to learn.

static Value parts_of(const std::tm& tm, int millis) {
    Value m = Value::make_map();
    m.map_set(Value(std::string("year")), Value((int64_t)tm.tm_year + 1900));
    m.map_set(Value(std::string("month")), Value((int64_t)tm.tm_mon + 1));      // 1..12
    m.map_set(Value(std::string("day")), Value((int64_t)tm.tm_mday));           // 1..31
    m.map_set(Value(std::string("hour")), Value((int64_t)tm.tm_hour));          // 0..23
    m.map_set(Value(std::string("minute")), Value((int64_t)tm.tm_min));
    m.map_set(Value(std::string("second")), Value((int64_t)tm.tm_sec));
    m.map_set(Value(std::string("millisecond")), Value((int64_t)millis));   // 0..999
    // ISO numbering, Monday = 1 to Sunday = 7. The C library counts Sunday as 0, which puts the
    // week-end at both ends and trips up every "is it a weekday" test.
    m.map_set(Value(std::string("weekday")), Value((int64_t)(tm.tm_wday == 0 ? 7 : tm.tm_wday)));
    m.map_set(Value(std::string("yearDay")), Value((int64_t)tm.tm_yday + 1));   // 1..366
    return m;
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

Value make_date_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("now")), Value::make_builtin(date_now));
    m.map_set(Value(std::string("utc")), Value::make_builtin(date_utc));
    return m;
}
