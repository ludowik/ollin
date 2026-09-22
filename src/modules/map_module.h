#pragma once
#include "../value.h"

Value make_map_module();

// True when fn is one of the map module's own functions (len, keys, values, has, delete) — used
// by CALL_METHOD to decide whether a map receiver gets self injected. See the comment there and
// on Map::kind (collections/map.h) for why this is done by function identity rather than by the
// receiver's kind.
bool is_map_module_fn(Value::BuiltinFn fn);
