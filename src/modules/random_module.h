#pragma once
#include "../rng.h"
#include "../value.h"

// The `Random` class: a generator of its own, which nothing else draws from. It is the engine's Rng (rng.h) behind
// a script object, so a seed gives the same numbers as math.seed does, on every platform.
Value make_random_class();

// The draws of math.rand and math.randInt, over any generator. `args` are the arguments of the call itself (a
// method's receiver is not among them), `fn` names the call in an error message.
Value rng_rand(Rng& rng, const Value* args, int argc, const char* fn);
Value rng_rand_int(Rng& rng, const Value* args, int argc, const char* fn);

// A Random instance's generator, and the hand-back of its state after a draw. `fn` names the caller in the refusal of
// something that is not a Random.
Rng random_load(const Value& obj, const char* fn);
void random_store(Value& obj, const Rng& rng);
