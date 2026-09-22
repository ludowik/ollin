// Free-function form of what a map already does through indexing and iteration (`m[k]`, `m.k`,
// `for k, v in m`) — a global "map" module, alongside `data`, `string` and the rest. `map.keys(m)`
// works on any map; so does `m.keys()`, the usual pseudo-method form — GET_INDEX serves these five
// names as a cold fallback (see op_GET_INDEX in vm.cpp), and CALL_METHOD recognizes them by
// function pointer (is_map_module_fn, below) to decide whether to inject `self`. It does NOT
// inject self for a map receiver in general — `math.sin(x)` must not hand `math` to `sin` as an
// extra argument, and every other module IS a map (Map::kind, collections/map.h) — only for a
// function resolved to be one of these five specifically, whatever map it was read from.
#include "map_module.h"
#include "module_utils.h"
#include "../vm.h"
#include <stdexcept>

static void map_check(const CallCtx& ctx, int min_argc, const char* sig) {
    if (ctx.argc < min_argc || !(ctx.args[0].is_map() || ctx.args[0].is_class()))
        throw std::runtime_error(std::string("map.") + sig);
}

static int map_len(CallCtx& ctx) {
    map_check(ctx, 1, "len: expected (map)");
    return ctx.ret(Value((int64_t)ctx.args[0].map_size()));
}

static int map_keys(CallCtx& ctx) {
    map_check(ctx, 1, "keys: expected (map)");
    Value out = Value::make_array();
    for (auto& [k, v] : ctx.args[0].mptr->data)
        out.array_push(k);
    return ctx.ret(out);
}

static int map_values(CallCtx& ctx) {
    map_check(ctx, 1, "values: expected (map)");
    Value out = Value::make_array();
    for (auto& [k, v] : ctx.args[0].mptr->data)
        out.array_push(v);
    return ctx.ret(out);
}

static int map_has(CallCtx& ctx) {
    map_check(ctx, 2, "has: expected (map, key)");
    return ctx.ret(Value::make_bool(ctx.args[0].mptr->find_ptr(ctx.args[1]) != nullptr));
}

// Removes the key and returns its former value, or nil when absent. Goes through Value::map_set
// (a nil value deletes, see Map::set) rather than a second data.erase(), so this shares the SAME
// enum-freeze guard as `m[k] = nil` in op_SET_INDEX — a frozen enum refuses both alike.
static int map_delete(CallCtx& ctx) {
    map_check(ctx, 2, "delete: expected (map, key)");
    if (ctx.args[0].mptr->kind == Map::ENUM)
        throw std::runtime_error("cannot modify an enum");
    Value old = ctx.args[0].map_get(ctx.args[1]);
    ctx.args[0].map_set(ctx.args[1], Value{});
    return ctx.ret(old);
}

Value make_map_module() {
    return MapBuilder()
        .fn("len", map_len)
        .fn("keys", map_keys)
        .fn("values", map_values)
        .fn("has", map_has)
        .fn("delete", map_delete)
        .done();
}

bool is_map_module_fn(Value::BuiltinFn fn) {
    return fn == map_len || fn == map_keys || fn == map_values || fn == map_has || fn == map_delete;
}
