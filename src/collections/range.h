#pragma once
// Included by chunk.h after iterator.h; do not include directly.
#include <cmath>

struct Range {
    int refcount = 1;
    double start;
    double end;
    double step;
    bool incl_right;
};

struct RangeIterator : Iterator {
    double current;
    double end;
    double step;
    bool incl_right;

    explicit RangeIterator(Range* r)
        : Iterator(KIND_RANGE), current(r->start), end(r->end), step(r->step), incl_right(r->incl_right) {
    }

    // Public and non-virtual, so FOR_ITER_NEXT1 can call it directly — devirtualized through
    // Iterator::kind — and inline it. next() and next_primary() remain the entry points of the
    // generic virtual protocol and delegate here.
    bool advance(Value& out) {
        bool done =
            (step > 0) ? (incl_right ? current > end : current >= end) : (incl_right ? current < end : current <= end);
        if (done)
            return false;
        // Falls back to an integer when current is an exact integer fitting in an int64;
        // double_fits_int64 guards the cast, see value.h.
        out = (double_fits_int64(current) && current == std::floor(current)) ? Value((int64_t)current)
                                                                           : Value(current);
        current += step;
        return true;
    }

  public:
    bool next(Value& key, Value& val) override {
        Value v;
        if (!advance(v))
            return false;
        key = val = v;
        return true;
    }
    bool next_primary(Value& out) override {
        return advance(out);
    }
    bool primary_is_val() const override {
        return true;
    }
};
