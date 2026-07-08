#pragma once
// Inclus par chunk.h après iterator.h — ne pas inclure directement.
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

    explicit RangeIterator(Range* r) : current(r->start), end(r->end), step(r->step), incl_right(r->incl_right) {
    }

  private:
    bool advance(Value& out) {
        bool done =
            (step > 0) ? (incl_right ? current > end : current >= end) : (incl_right ? current < end : current <= end);
        if (done)
            return false;
        // borne haute STRICTE (< 2^63) : (double)INT64_MAX arrondit à 2^63, non
        // représentable en int64 → le cast serait UB. -2^63 (INT64_MIN) l'est.
        out = (current == std::floor(current) && current >= -9223372036854775808.0 &&
               current < 9223372036854775808.0)
                  ? Value((int64_t)current)
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
