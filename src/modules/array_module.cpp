#include "array_module.h"
#include "../vm.h"
#include <stdexcept>

static int arr_map(CallCtx& ctx) {
    if (ctx.argc < 2 || !ctx.args[0].is_array())
        throw std::runtime_error("array.map: expected (array, fn)");
    Value& arr = ctx.args[0];
    Value& fn  = ctx.args[1];
    int64_t n = arr.array_size();
    Value result = Value::make_array();
    for (int64_t i = 0; i < n; i++) {
        Value val = arr.array_get(i + 1);
        Value idx((int64_t)(i + 1));
        Value args[2] = {val, idx};
        result.array_push(ctx.vm->call_value(fn, args, 2));
    }
    return ctx.ret(result);
}

static int arr_filter(CallCtx& ctx) {
    if (ctx.argc < 2 || !ctx.args[0].is_array())
        throw std::runtime_error("array.filter: expected (array, fn)");
    Value& arr = ctx.args[0];
    Value& fn  = ctx.args[1];
    int64_t n = arr.array_size();
    Value result = Value::make_array();
    for (int64_t i = 0; i < n; i++) {
        Value val = arr.array_get(i + 1);
        Value idx((int64_t)(i + 1));
        Value args[2] = {val, idx};
        if (!is_falsy(ctx.vm->call_value(fn, args, 2)))
            result.array_push(val);
    }
    return ctx.ret(result);
}

static int arr_reduce(CallCtx& ctx) {
    if (ctx.argc < 3 || !ctx.args[0].is_array())
        throw std::runtime_error("array.reduce: expected (array, fn, init)");
    Value& arr = ctx.args[0];
    Value& fn  = ctx.args[1];
    Value acc  = ctx.args[2];
    int64_t n = arr.array_size();
    for (int64_t i = 0; i < n; i++) {
        Value val = arr.array_get(i + 1);
        Value idx((int64_t)(i + 1));
        Value args[3] = {acc, val, idx};
        acc = ctx.vm->call_value(fn, args, 3);
    }
    return ctx.ret(acc);
}

Value make_array_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("map")),    Value::make_builtin(arr_map));
    m.map_set(Value(std::string("filter")), Value::make_builtin(arr_filter));
    m.map_set(Value(std::string("reduce")), Value::make_builtin(arr_reduce));
    return m;
}
