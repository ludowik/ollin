## Regression tests — The data module.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/data.ol — it must finish without error.

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
data.set("bf", nil)
data.set("bn", nil)
data.set("bs", nil)
