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
// date.weekdayName(day[, language[, form]])  the name of a weekday (1 = Monday to 7 = Sunday, as the
//                `weekday` field numbers it), in "en" or "fr", "long" ("Monday") or "short" ("Mon").
// date.monthName(month[, language[, form]])  the same for a month (1 = January to 12 = December).
//                The names are data of the calendar, not a formatting: a script that shows them in another
//                language asks for it here, and a language is one more row of each table below.
//
// The first three return a plain map, like graphics.modelSize: no class, no method, nothing to learn.

// The weekday is numbered ISO, Monday = 1 to Sunday = 7: the C library counts Sunday as 0, which puts
// the week-end at both ends and trips up every "is it a weekday" test.
static Value make_parts(long long year, int month, int day, int hour, int minute, int second, int millis, int weekday,
                        int year_day) {
    return MapBuilder()
        .int_num("year", year)
        .int_num("month", month)        // 1..12
        .int_num("day", day)            // 1..31
        .int_num("hour", hour)          // 0..23
        .int_num("minute", minute)
        .int_num("second", second)
        .int_num("millisecond", millis) // 0..999
        .int_num("weekday", weekday)
        .int_num("yearDay", year_day)   // 1..366
        .done();
}

static Value parts_of(const std::tm& tm, int millis) {
    return make_parts(tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec, millis,
                      tm.tm_wday == 0 ? 7 : tm.tm_wday, tm.tm_yday + 1);
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

// February has 29 days by the Gregorian rule: every fourth year, except the centuries that 400 does not divide.
static int month_length(long long year, int month) {
    static const int days[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    bool leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    return month == 2 && leap ? 29 : days[month - 1];
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
    if (text.size() != 10)
        return ctx.ret(Value());
    int year = 0;
    int month = 0;
    int day = 0;
    for (int i = 0; i < 10; ++i) {
        char c = text[i];
        if (i == 4 || i == 7) {
            if (c != '-')
                return ctx.ret(Value());
        } else if (c < '0' || c > '9') {
            return ctx.ret(Value());
        } else if (i < 4) {
            year = year * 10 + (c - '0');
        } else if (i < 7) {
            month = month * 10 + (c - '0');
        } else {
            day = day * 10 + (c - '0');
        }
    }
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > month_length(year, month))
        return ctx.ret(Value());
    long long days = days_from_civil(year, month, day);
    int weekday = (int)(((days + 3) % 7 + 7) % 7) + 1; // 1970-01-01 was a Thursday, the 4th day of an ISO week
    int year_day = (int)(days - days_from_civil(year, 1, 1)) + 1;
    return ctx.ret(make_parts(year, month, day, 0, 0, 0, 0, weekday, year_day));
}

// A year this far from 0 is no date anyone means, and the cast to int stays far from its limit.
static const long long k_max_year = 1000000000;

static int date_month_length(CallCtx& ctx) {
    const char* fn = "date.monthLength";
    long long year = whole_arg(ctx.args, ctx.argc, 0, fn, "year", -k_max_year, k_max_year);
    long long month = whole_arg(ctx.args, ctx.argc, 1, fn, "month", 1, 12);
    return ctx.ret(Value((int64_t)month_length(year, (int)month)));
}

// The languages the names exist in, and the forms they come in. Both lists are what mode_arg accepts and
// what its error message spells out; the tables below follow the same order (language, form, number).
static const char* const k_languages[] = {"en", "fr"};
static const char* const k_forms[] = {"long", "short"};
static const char* const k_weekday_names[2][2][7] = {
    {
        {"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"},
        {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"},
    },
    {
        {"lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"},
        {"lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."},
    },
};
static const char* const k_month_names[2][2][12] = {
    {
        {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
         "November", "December"},
        {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"},
    },
    {
        {"janvier", "f\u00e9vrier", "mars", "avril", "mai", "juin", "juillet", "ao\u00fbt", "septembre", "octobre",
         "novembre", "d\u00e9cembre"},
        {"janv.", "f\u00e9vr.", "mars", "avr.", "mai", "juin", "juil.", "ao\u00fbt", "sept.", "oct.", "nov.",
         "d\u00e9c."},
    },
};

// The name of the weekday or month `ctx.args[0]` numbers, in the language and the form asked for. `what` names
// the number in the error ("day", "month"); the table's sizes are checked against the two lists above.
template <int L, int F, int N>
static int date_name(CallCtx& ctx, const char* fn, const char* what, const char* const (&names)[L][F][N]) {
    static_assert(L == sizeof(k_languages) / sizeof(k_languages[0]), "every language needs its names");
    static_assert(F == sizeof(k_forms) / sizeof(k_forms[0]), "every form needs its names");
    int number = (int)whole_arg(ctx.args, ctx.argc, 0, fn, what, 1, N);
    int language = mode_arg(ctx, 1, fn, k_languages, 0);
    int form = mode_arg(ctx, 2, fn, k_forms, 0);
    return ctx.ret(Value(std::string(names[language][form][number - 1])));
}

static int date_weekday_name(CallCtx& ctx) {
    return date_name(ctx, "date.weekdayName", "day", k_weekday_names);
}

static int date_month_name(CallCtx& ctx) {
    return date_name(ctx, "date.monthName", "month", k_month_names);
}

Value make_date_module() {
    return MapBuilder()
        .fn("now", date_now)
        .fn("utc", date_utc)
        .fn("parse", date_parse)
        .fn("monthLength", date_month_length)
        .fn("weekdayName", date_weekday_name)
        .fn("monthName", date_month_name)
        .done();
}
