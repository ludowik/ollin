// Pseudo-méthodes des tableaux (arr.len(), arr.push(v), arr.map(fn)…).
//
// Construites UNE fois au démarrage dans une map, comme le module `string` :
// GET_INDEX résout `arr.<m>` par un simple lookup (cf. VM::array_module_) au lieu
// d'une chaîne de comparaisons de chaînes reconstruisant une closure par accès.
//
// Le tableau est le PREMIER argument : CALL_METHOD injecte le receveur en self
// pour un tableau, donc `arr.push(v)` arrive ici en (arr, v).
#include "array_module.h"
#include "../vm.h"
#include <algorithm>
#include <stdexcept>

// Convention de message uniforme : « array.<methode>: expected (array, <params>) ».
// Le nom reste préfixé `array.` — c'est la même fonction native quelle que soit la
// forme d'appel.
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

static int arr_map(CallCtx& ctx) {
    arr_check(ctx, 2, "map: expected (array, fn)");
    Value& arr = ctx.args[0];
    Value& fn = ctx.args[1];
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
    Value& arr = ctx.args[0];
    Value& fn = ctx.args[1];
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
    Value& arr = ctx.args[0];
    Value& fn = ctx.args[1];
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

// Tri en place, stable. Sans comparateur : ordre par RANG DE TYPE
// (nil < nombres < chaînes < reste), puis par valeur au sein d'un même rang.
static int arr_sort(CallCtx& ctx) {
    arr_check(ctx, 1, "sort: expected (array[, cmp])");
    Value& arr = ctx.args[0];
    if (ctx.argc >= 2 && ctx.args[1].is_callable()) {
        Value fn = ctx.args[1];
        VM* vm = ctx.vm;
        // Une exception levée par le comparateur ne peut pas traverser stable_sort
        // (UB) : on la capture, on rend un ordre stable, puis on la relance après.
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
