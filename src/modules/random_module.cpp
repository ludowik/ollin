#include "random_module.h"
#include "module_utils.h"
#include <stdexcept>
#include <string>

// The state of the generator is an integer field of the instance, so that a copy of the object copies the sequence.
static const char* const k_state_key = "state";

Value rng_rand(Rng& rng, const Value* args, int argc, const char* fn) {
    double r = rng.unit();
    if (argc == 0)
        return Value(r);
    if (argc == 1)
        return Value(r * num_arg(args, argc, 0, fn));
    double lo = num_arg(args, argc, 0, fn);
    double hi = num_arg(args, argc, 1, fn);
    return Value(lo + r * (hi - lo));
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

static int random_rand(CallCtx& ctx);

// Whether obj comes from the Random class, or from one that extends it: recognised by the class's own `rand` being OUR
// function, so a script that reassigns the global `Random` does not turn the generators already made into strangers.
static bool is_random(const Value& obj) {
    if (!obj.is_map())
        return false;
    for (const Value* c = &obj.class_of(); c->is_class(); c = &c->class_of()) {
        Value fn = c->map_get(Value(std::string("rand")));
        if (fn.is_builtin() && fn.as_builtin() == random_rand)
            return true;
    }
    return false;
}

Rng random_load(const Value& obj, const char* fn) {
    if (!is_random(obj))
        throw std::runtime_error(std::string(fn) + ": expected a Random, got " + obj.type_name());
    Value state = obj.map_get(Value(std::string(k_state_key)));
    if (!state.is_integer())
        throw std::runtime_error(std::string(fn) + ": the state of the Random is not an integer");
    return Rng((uint64_t)state.as_int());
}

void random_store(Value& obj, const Rng& rng) {
    obj.map_set(Value(std::string(k_state_key)), Value((int64_t)rng.state));
}

// Random([seed]): no seed takes one from the clock, as the engine's own generator does at startup.
static int random_init(CallCtx& ctx) {
    uint64_t seed = ctx.argc >= 2 ? (uint64_t)int_arg(ctx.args + 1, ctx.argc - 1, 0, "Random") : rng_clock_seed();
    random_store(ctx.args[0], Rng(seed));
    return ctx.ret(Value{});
}

static int random_seed(CallCtx& ctx) {
    Rng rng = random_load(ctx.args[0], "Random.seed");
    rng.seed((uint64_t)int_arg(ctx.args + 1, ctx.argc - 1, 0, "Random.seed"));
    random_store(ctx.args[0], rng);
    return ctx.ret(Value{});
}

static int random_rand(CallCtx& ctx) {
    Rng rng = random_load(ctx.args[0], "Random.rand");
    Value result = rng_rand(rng, ctx.args + 1, ctx.argc - 1, "Random.rand");
    random_store(ctx.args[0], rng);
    return ctx.ret(result);
}

static int random_rand_int(CallCtx& ctx) {
    Rng rng = random_load(ctx.args[0], "Random.randInt");
    Value result = rng_rand_int(rng, ctx.args + 1, ctx.argc - 1, "Random.randInt");
    random_store(ctx.args[0], rng);
    return ctx.ret(result);
}

Value make_random_class() {
    return MapBuilder(Value::make_class("Random"))
        .fn("init", random_init)
        .fn("seed", random_seed)
        .fn("rand", random_rand)
        .fn("randInt", random_rand_int)
        .done();
}
