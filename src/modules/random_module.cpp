#include "random_module.h"
#include "module_utils.h"

// The state of the generator is an integer field of the instance, so that a copy of the object copies the sequence.
static const Value& state_key() {
    static const Value key(std::string("state"));   // built once: a draw would otherwise intern and hash it twice
    return key;
}

// The arguments are checked BEFORE the draw: a refused call leaves the generator where it was.
Value rng_rand(Rng& rng, const Value* args, int argc, const char* fn) {
    if (argc == 0)
        return Value(rng.unit());
    if (argc == 1) {
        double hi = num_arg(args, argc, 0, fn);
        return Value(rng.unit() * hi);
    }
    double lo = num_arg(args, argc, 0, fn);
    double hi = num_arg(args, argc, 1, fn);
    return Value(lo + rng.unit() * (hi - lo));
}

Value rng_rand_int(Rng& rng, const Value* args, int argc, const char* fn) {
    if (argc == 0)
        throw std::runtime_error(std::string(fn) + ": at least one argument required");
    if (argc == 1) {
        int64_t hi = int_arg(args, argc, 0, fn);
        if (hi <= 0)
            throw std::runtime_error(std::string(fn) + ": argument must be > 0");
        return Value(rng.between(1, hi));
    }
    int64_t lo = int_arg(args, argc, 0, fn);
    int64_t hi = int_arg(args, argc, 1, fn);
    if (lo > hi)
        throw std::runtime_error(std::string(fn) + ": lo must be <= hi");
    return Value(rng.between(lo, hi));
}

static void require_random(const Value& obj, const char* fn) {
    if (!obj.is_instance_of(make_random_class()))
        throw std::runtime_error(std::string(fn) + ": expected a Random, got " + obj.type_name());
}

static Rng random_load(const Value& obj, const char* fn) {
    require_random(obj, fn);
    Value state = obj.map_get(state_key());
    if (!state.is_integer())
        throw std::runtime_error(std::string(fn) + ": the state of the Random is not an integer");
    return Rng((uint64_t)state.as_int());
}

static void random_store(Value& obj, const Rng& rng) {
    obj.map_set(state_key(), Value((int64_t)rng.state));
}

RandomScope::RandomScope(const Value& obj, const char* fn)
    : obj_(obj),
      rng_(random_load(obj, fn)) {
}

RandomScope::~RandomScope() {
    random_store(obj_, rng_);
}

// Random([seed]): no seed takes one from the clock, as the engine's own generator does at startup.
static int random_init(CallCtx& ctx) {
    require_random(ctx.args[0], "Random");
    uint64_t seed = ctx.argc >= 2 ? (uint64_t)int_arg(ctx.args + 1, ctx.argc - 1, 0, "Random") : rng_clock_seed();
    random_store(ctx.args[0], Rng(seed));
    return ctx.ret(Value{});
}

static int random_seed(CallCtx& ctx) {
    RandomScope scope(ctx.args[0], "Random.seed");
    scope.rng().seed((uint64_t)int_arg(ctx.args + 1, ctx.argc - 1, 0, "Random.seed"));
    return ctx.ret(Value{});
}

// The draw of a method: the receiver's generator, the arguments after it.
static int random_draw(CallCtx& ctx, const char* fn, Value (*draw)(Rng&, const Value*, int, const char*)) {
    RandomScope scope(ctx.args[0], fn);
    return ctx.ret(draw(scope.rng(), ctx.args + 1, ctx.argc - 1, fn));
}

static int random_rand(CallCtx& ctx) {
    return random_draw(ctx, "Random.rand", rng_rand);
}

static int random_rand_int(CallCtx& ctx) {
    return random_draw(ctx, "Random.randInt", rng_rand_int);
}

static Value build_random_class() {
    return MapBuilder(Value::make_class("Random"))
        .fn("init", random_init)
        .fn("seed", random_seed)
        .fn("rand", random_rand)
        .fn("randInt", random_rand_int)
        .done();
}

Value make_random_class() {
    static Value cls = build_random_class();
    return cls;
}
