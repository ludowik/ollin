## Regression tests — The data module.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/data.ol — it must finish without error.

## ── data: a boolean survives persistence ───────────────────────────────────
## The regression: `encode_value` knew only integers, floats and strings, so `data.set(k, true)`
## failed as soon as `true` stopped being the integer 1 — and failed with a message that promised
## booleans. The module had no behaviour test at all.
data.set("bt", true)
data.set("bf", false)
data.set("bn", 42)
data.set("bs", "x")
assert(data.get("bt") == true)
assert(data.get("bf") == false)
assert(data.get("bn") == 42 and data.get("bs") == "x")
assert(data.has("bt") and not data.has("never_written"))

## The type survives the encoding: what comes back is a BOOLEAN, not the integer 1.
assert(data.get("bt") <> 1)
assert(data.get("bf") <> 0)

## The default value of a missing key, and deletion through nil.
assert(data.get("never_written", "defaut") == "defaut")
data.set("bt", nil)
assert(not data.has("bt"))

## ── data: the shared scope, keys, clear, floats and awkward strings ──
## The two scopes are separate stores with the same six operations. (What survives from one RUN to the
## next — the sidecar file — is guarded by tests/check_data_persistence.sh: it needs two processes, and
## it is also where shared.clear() is run, with a HOME of its own: the shared store is ONE file in the
## real home directory, and this test must never empty what other programs keep there.)
data.set("pk", "project")
data.shared.set("ollin_test_sk", "shared")
assert(data.get("pk") == "project" and not data.has("ollin_test_sk"), "a key of one scope is not seen by the other")
assert(data.shared.get("ollin_test_sk") == "shared" and not data.shared.has("pk"))
assert(data.shared.get("ollin_test_none", 7) == 7)
data.shared.set("ollin_test_sk", nil)
assert(not data.shared.has("ollin_test_sk"))

## Floats keep every digit, and keep their type next to the integers.
data.set("pf", 0.1)
data.set("pi3", 3)
assert(data.get("pf") == 0.1 and typeof(data.get("pi3")) == "int")
data.set("pf", 1 / 3)
assert(data.get("pf") == 1 / 3, "17 significant digits: the float comes back identical")

## A string is stored raw: quotes, backslashes, newlines, tabs and control characters change nothing.
var weird = "q" + string.fromCode(34) + string.fromCode(92) + string.fromCode(10) + string.fromCode(13) + string.fromCode(9) + string.fromCode(1) + string.fromCode(27) + "é"
data.set("pw", weird)
assert(data.get("pw") == weird)
assert(data.get("pw").len() == weird.len())
data.set("pe", "")
assert(data.has("pe") and data.get("pe") == "", "an empty string is a value, not an absence")

## keys lists what is there, delete removes one key and clear all of them.
var before = len(data.keys())
data.delete("pe")
assert(len(data.keys()) == before - 1 and not data.has("pe"))
data.delete("never_existed")
assert(len(data.keys()) == before - 1, "deleting an absent key is harmless")
data.clear()
assert(len(data.keys()) == 0 and not data.has("pk"))

## the shared store lists its keys too (read only: it is a single file of the machine, never cleared here)
assert(typeof(data.shared.keys()) == "array")
