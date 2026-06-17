#pragma once
// Inclus par chunk.h après iterator.h — ne pas inclure directement.

struct Range {
    int     refcount = 1;
    int64_t start;
    int64_t end;
    int64_t step;
    bool    incl_right;
};

struct RangeIterator : Iterator {
    int64_t current;
    int64_t end;
    int64_t step;
    bool    incl_right;

    explicit RangeIterator(Range* r)
        : current(r->start), end(r->end), step(r->step), incl_right(r->incl_right) {}

    bool next(Value& key, Value& val) override {
        bool done;
        if (step > 0) done = incl_right ? (current > end) : (current >= end);
        else          done = incl_right ? (current < end) : (current <= end);
        if (done) return false;
        key = Value(current);
        val = Value(current);
        current += step;
        return true;
    }
};
