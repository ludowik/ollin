#pragma once
#include "../rng.h"
#include "../value.h"

// The `Random` class: a generator of its own, which nothing else draws from. It is the engine's Rng (rng.h) behind
// a script object, so a seed gives the same numbers as math.seed does, on every platform. One class for the whole
// program, as for Quat: an instance is recognised by it, whatever a script does with the global `Random`.
Value make_random_class();

// The draws of math.rand and math.randInt, over any generator. `args` are the arguments of the call itself (a
// method's receiver is not among them), `fn` names the call in an error message.
Value rng_rand(Rng& rng, const Value* args, int argc, const char* fn);
Value rng_rand_int(Rng& rng, const Value* args, int argc, const char* fn);

// The generator of a Random instance for the length of a scope: loaded from the instance's state, handed back to it
// at the end. `fn` names the caller in the refusal of something that is not a Random. It keeps its own reference to
// the instance, since a builtin overwrites its first argument with its result.
class RandomScope {
public:
    RandomScope(const Value& obj, const char* fn);
    ~RandomScope();
    RandomScope(const RandomScope&) = delete;
    RandomScope& operator=(const RandomScope&) = delete;

    Rng& rng() {
        return rng_;
    }

private:
    Value obj_;
    Rng rng_;
};
