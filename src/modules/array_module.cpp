// Array pseudo-methods: arr.len(), arr.push(v), arr.map(fn) and so on.
//
// They are built ONCE at startup into a map, like the `string` module, so that GET_INDEX resolves
// `arr.<m>` with a plain lookup (see VM::array_module_) instead of a chain of string comparisons
// rebuilding a closure on every access.
//
// The array is the FIRST argument: CALL_METHOD injects the receiver as self for an array, so
// `arr.push(v)` arrives here as (arr, v).
#include "array_module.h"
#include "../vm.h"
#include <algorithm>
#include <stdexcept>

// Uniform message convention: "array.<method>: expected (array, <params>)". The name keeps the
// `array.` prefix because it is the same native function whatever the call form.
static void arr_check(const CallCtx& ctx, int min_argc, const char* sig) {
    if (ctx.argc < min_argc || !ctx.args[0].is_array())
        throw std::runtime_error(std::string("array.") + sig);
}

static int arr_len(CallCtx& ctx) {
    arr_check(ctx, 1, "len: expected (array)");
    return ctx.ret(Value((int64_t)ctx.args[0].array_size()));
}

static int arr_push(CallCtx& ctx) {
    arr_check(ctx, 1, "push: expected (array, value)");
    if (ctx.argc >= 2)
        ctx.args[0].array_push(ctx.args[1]);
    return ctx.ret(ctx.args[0]);
}

static int arr_pop(CallCtx& ctx) {
    arr_check(ctx, 1, "pop: expected (array)");
    return ctx.ret(ctx.args[0].array_pop());
}

static int arr_dequeue(CallCtx& ctx) {
    arr_check(ctx, 1, "dequeue: expected (array)");
    return ctx.ret(ctx.args[0].array_shift());
}

// insert(v) = push ; insert(i, v) = insertion positionnelle (index 1-based).
static int arr_insert(CallCtx& ctx) {
    arr_check(ctx, 1, "insert: expected (array[, index], value)");
    if (ctx.argc == 2)
        ctx.args[0].array_push(ctx.args[1]);
    else if (ctx.argc >= 3 && ctx.args[1].is_integer())
        ctx.args[0].array_insert(ctx.args[1].as_int(), ctx.args[2]);
    return ctx.ret(ctx.args[0]);
}

static int arr_delete(CallCtx& ctx) {
    arr_check(ctx, 1, "delete: expected (array, index)");
    if (ctx.argc >= 2 && ctx.args[1].is_integer())
        return ctx.ret(ctx.args[0].array_remove(ctx.args[1].as_int()));
    return ctx.ret(Value{});
}

// The higher-order members below COPY the array and the function out of `ctx.args` before running
// any Ollin code: `call_value` can grow the register file, which reallocates it, and a reference
// into it would then dangle — `[1, 2, 3].map(f)` with a deeply recursive `f` gave back nil values.
// Copying the array Value keeps the same Array*, so `sort` still sorts in place.
static int arr_map(CallCtx& ctx) {
    arr_check(ctx, 2, "map: expected (array, fn)");
    Value arr = ctx.args[0];
    Value fn = ctx.args[1];
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
    arr_check(ctx, 2, "filter: expected (array, fn)");
    Value arr = ctx.args[0];
    Value fn = ctx.args[1];
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
    arr_check(ctx, 3, "reduce: expected (array, fn, init)");
    Value arr = ctx.args[0];
    Value fn = ctx.args[1];
    Value acc = ctx.args[2];
    int64_t n = arr.array_size();
    for (int64_t i = 0; i < n; i++) {
        Value val = arr.array_get(i + 1);
        Value idx((int64_t)(i + 1));
        Value args[3] = {acc, val, idx};
        acc = ctx.vm->call_value(fn, args, 3);
    }
    return ctx.ret(acc);
}

// In-place stable sort. Without a comparator the order is by TYPE RANK (nil < numbers < strings
// < the rest), then by value within a rank.
static int arr_sort(CallCtx& ctx) {
    arr_check(ctx, 1, "sort: expected (array[, cmp])");
    Value arr = ctx.args[0];
    if (ctx.argc >= 2 && ctx.args[1].is_callable()) {
        Value fn = ctx.args[1];
        VM* vm = ctx.vm;
        // An exception thrown by the comparator cannot cross stable_sort (that would be UB), so it
        // is captured, a stable order is returned, and it is rethrown afterwards.
        std::exception_ptr ex;
        std::stable_sort(arr.aptr->items.begin(), arr.aptr->items.end(), [&fn, vm, &ex](const Value& a, const Value& b) {
            if (ex)
                return false;
            try {
                Value args[2] = {a, b};
                return !is_falsy(vm->call_value(fn, args, 2));
            } catch (...) {
                ex = std::current_exception();
                return false;
            }
        });
        if (ex)
            std::rethrow_exception(ex);
    } else {
        auto type_rank = [](const Value& v) -> int {
            if (v.is_nil())
                return 0;
            if (v.is_integer() || v.is_float())
                return 1;
            if (v.is_string())
                return 2;
            return 3;
        };
        std::stable_sort(arr.aptr->items.begin(), arr.aptr->items.end(), [&type_rank](const Value& a, const Value& b) {
            int ra = type_rank(a), rb = type_rank(b);
            if (ra != rb)
                return ra < rb;
            if (ra == 1)
                return a.as_num() < b.as_num();
            if (ra == 2)
                return a.as_string() < b.as_string();
            return false;
        });
    }
    return ctx.ret(arr);
}

Value make_array_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("len")), Value::make_builtin(arr_len));
    m.map_set(Value(std::string("push")), Value::make_builtin(arr_push));
    m.map_set(Value(std::string("enqueue")), Value::make_builtin(arr_push));
    m.map_set(Value(std::string("pop")), Value::make_builtin(arr_pop));
    m.map_set(Value(std::string("dequeue")), Value::make_builtin(arr_dequeue));
    m.map_set(Value(std::string("insert")), Value::make_builtin(arr_insert));
    m.map_set(Value(std::string("delete")), Value::make_builtin(arr_delete));
    m.map_set(Value(std::string("map")), Value::make_builtin(arr_map));
    m.map_set(Value(std::string("filter")), Value::make_builtin(arr_filter));
    m.map_set(Value(std::string("reduce")), Value::make_builtin(arr_reduce));
    m.map_set(Value(std::string("sort")), Value::make_builtin(arr_sort));
    return m;
}
