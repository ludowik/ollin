// Free-function form of what a map already does through indexing and iteration (`m[k]`, `m.k`,
// `for k, v in m`) — a global "map" module, alongside `data`, `string` and the rest. `map.keys(m)`
// works on any map; so does `m.keys()`, the usual pseudo-method form — GET_INDEX serves these
// names as a cold fallback (see op_GET_INDEX in vm.cpp), and CALL_METHOD recognizes them by
// function pointer (is_map_module_fn, below) to decide whether to inject `self`. It does NOT
// inject self for a map receiver in general — `math.sin(x)` must not hand `math` to `sin` as an
// extra argument, and every other module IS a map (Map::kind, collections/map.h) — only for a
// function resolved to be one of these specifically, whatever map it was read from.
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

// Shared by map_keys/map_values: same loop, only which half of the pair is collected differs.
// Reserves up front — the map's size is already known, unlike a script building an array by hand.
static Value map_collect(const Value& m, bool want_key) {
    Value out = Value::make_array();
    out.aptr->items.reserve(m.mptr->data.size());
    for (auto& [k, v] : m.mptr->data)
        out.array_push(want_key ? k : v);
    return out;
}

static int map_keys(CallCtx& ctx) {
    map_check(ctx, 1, "keys: expected (map)");
    return ctx.ret(map_collect(ctx.args[0], true));
}

static int map_values(CallCtx& ctx) {
    map_check(ctx, 1, "values: expected (map)");
    return ctx.ret(map_collect(ctx.args[0], false));
}

static int map_has(CallCtx& ctx) {
    map_check(ctx, 2, "has: expected (map, key)");
    return ctx.ret(Value::make_bool(ctx.args[0].mptr->find_ptr(ctx.args[1]) != nullptr));
}

// Removes the key and returns its former value, or nil when absent. Map::set itself is
// deliberately NOT enum-guarded (it is also how a module's own data, and an enum's members
// before SEAL_ENUM, get written — see "Type enum" in CLAUDE.md), so the guard is repeated here
// at the script-facing call site, same as op_SET_INDEX's for `m[k] = nil` — same wording, so a
// frozen enum reads the same complaint through either spelling.
static int map_delete(CallCtx& ctx) {
    map_check(ctx, 2, "delete: expected (map, key)");
    const Value& key = ctx.args[1];
    if (ctx.args[0].mptr->kind == Map::ENUM)
        throw std::runtime_error("cannot modify an enum" + (key.is_string() ? " (field '" + key.as_string() + "')" : ""));
    Value old = ctx.args[0].map_get(key);
    ctx.args[0].map_set(key, Value{});
    return ctx.ret(old);
}

// Refused: what an enum, a module or a class holds is its definition. An instance keeps its class.
static int map_clear(CallCtx& ctx) {
    map_check(ctx, 1, "clear: expected (map)");
    Map& m = *ctx.args[0].mptr;
    if (m.kind == Map::ENUM)
        throw std::runtime_error("cannot modify an enum");
    if (m.kind == Map::MODULE || ctx.args[0].is_class())
        throw std::runtime_error("map.clear: a module or a class cannot be cleared");
    if (m.data.size() > MapPool::POOL_MAX_SIZE)
        decltype(m.data){}.swap(m.data);   // a big map gives its buckets back: the pool would keep them pinned
    else
        m.data.clear();
    m.mark_rebuilt();
    return ctx.ret(ctx.args[0]);
}

// SHALLOW; the result is always a plain map (a frozen enum becomes writable), and an instance keeps its class.
// A class is refused: its entries are its methods.
static int map_copy(CallCtx& ctx) {
    map_check(ctx, 1, "copy: expected (map)");
    if (ctx.args[0].is_class())
        throw std::runtime_error("map.copy: a class cannot be copied");
    const Map& source = *ctx.args[0].mptr;
    Value result = Value::make_map();
    result.mptr->data = source.data;   // one allocation at the right size, where Map::set would rehash as it grows
    result.mptr->mark_rebuilt();
    result.set_class(source.proto);
    return ctx.ret(result);
}

// The single list of the module's own functions: both make_map_module (the module's content) and
// is_map_module_fn (CALL_METHOD's self-injection test) read it, so a pseudo-method added to
// one and forgotten in the other can't happen — the old two-list form let exactly that compile
// silently, m.newFn() then just never getting self.
static const struct { const char* name; Value::BuiltinFn fn; } k_map_fns[] = {
    {"len", map_len},       {"keys", map_keys}, {"values", map_values}, {"has", map_has},
    {"delete", map_delete}, {"copy", map_copy}, {"clear", map_clear},
};

Value make_map_module() {
    MapBuilder b;
    for (auto& e : k_map_fns)
        b.fn(e.name, e.fn);
    return b.done();
}

bool is_map_module_fn(Value::BuiltinFn fn) {
    for (auto& e : k_map_fns)
        if (e.fn == fn)
            return true;
    return false;
}
