#pragma once
// Inclus par chunk.h après iterator.h — ne pas inclure directement.
#include <cmath>

struct Range {
    int    refcount = 1;
    double start;
    double end;
    double step;
    bool   incl_right;
};

struct RangeIterator : Iterator {
    double current;
    double end;
    double step;
    bool   incl_right;

    explicit RangeIterator(Range* r)
        : current(r->start), end(r->end), step(r->step), incl_right(r->incl_right) {}

    bool next(Value& key, Value& val) override {
        bool done;
        if (step > 0) done = incl_right ? (current > end) : (current >= end);
        else          done = incl_right ? (current < end) : (current <= end);
        if (done) return false;
        Value v = (current == std::floor(current) && current >= (double)INT64_MIN && current <= (double)INT64_MAX)
                  ? Value((int64_t)current) : Value(current);
        key = v; val = v;
        current += step;
        return true;
    }
    bool next_primary(Value& out) override {
        bool done;
        if (step > 0) done = incl_right ? (current > end) : (current >= end);
        else          done = incl_right ? (current < end) : (current <= end);
        if (done) return false;
        out = (current == std::floor(current) && current >= (double)INT64_MIN && current <= (double)INT64_MAX)
              ? Value((int64_t)current) : Value(current);
        current += step;
        return true;
    }
    bool primary_is_val() const override { return true; }
};
