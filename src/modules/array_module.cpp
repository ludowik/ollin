#include "array_module.h"
#include "../vm.h"
#include <stdexcept>

static int arr_map(CallCtx& ctx) {
    if (ctx.argc < 2 || !ctx.args[0].isArray())
        throw std::runtime_error("array.map: expected (array, fn)");
    Value& arr = ctx.args[0];
    Value& fn  = ctx.args[1];
    int64_t n = arr.arraySize();
    Value result = Value::makeArray();
    for (int64_t i = 0; i < n; i++) {
        Value val = arr.arrayGet(i + 1);
        Value idx((int64_t)(i + 1));
        Value args[2] = {val, idx};
        result.arrayPush(ctx.vm->callValue(fn, args, 2));
    }
    return ctx.ret(result);
}

static int arr_filter(CallCtx& ctx) {
    if (ctx.argc < 2 || !ctx.args[0].isArray())
        throw std::runtime_error("array.filter: expected (array, fn)");
    Value& arr = ctx.args[0];
    Value& fn  = ctx.args[1];
    int64_t n = arr.arraySize();
    Value result = Value::makeArray();
    for (int64_t i = 0; i < n; i++) {
        Value val = arr.arrayGet(i + 1);
        Value idx((int64_t)(i + 1));
        Value args[2] = {val, idx};
        if (!isFalsy(ctx.vm->callValue(fn, args, 2)))
            result.arrayPush(val);
    }
    return ctx.ret(result);
}

static int arr_reduce(CallCtx& ctx) {
    if (ctx.argc < 3 || !ctx.args[0].isArray())
        throw std::runtime_error("array.reduce: expected (array, fn, init)");
    Value& arr = ctx.args[0];
    Value& fn  = ctx.args[1];
    Value acc  = ctx.args[2];
    int64_t n = arr.arraySize();
    for (int64_t i = 0; i < n; i++) {
        Value val = arr.arrayGet(i + 1);
        Value idx((int64_t)(i + 1));
        Value args[3] = {acc, val, idx};
        acc = ctx.vm->callValue(fn, args, 3);
    }
    return ctx.ret(acc);
}

Value makeArrayModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("map")),    Value::makeBuiltin(arr_map));
    m.mapSet(Value(std::string("filter")), Value::makeBuiltin(arr_filter));
    m.mapSet(Value(std::string("reduce")), Value::makeBuiltin(arr_reduce));
    return m;
}
