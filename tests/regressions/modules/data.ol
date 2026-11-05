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

## ── data: arrays and maps ──────────────────────────────────────────────────────────────────────────
## A value is no longer a scalar only: an array or a map is kept whole, to any depth, and comes back as a copy of what was
## written — changing one afterwards changes the other no more. (A game keeps its whole state this way.)
data.clear()
data.set("list", [1, 2.5, "x", true, nil, [3, 4], {k: 1}])
var list = data.get("list")
assert(len(list) == 7 and list[1] == 1 and list[3] == "x" and list[4] == true and list[5] == nil)
assert(typeof(list[1]) == "int" and typeof(list[2]) == "float", "an integer stays an integer, a float a float")
assert(list[2] == 2.5 and list[6][2] == 4 and list[7].k == 1)
var two = 4 / 2                                  ## a division gives a float even when the value is whole (a literal 2.0 is an integer)
assert(typeof(two) == "float")
data.set("whole", [two, 2])
assert(typeof(data.get("whole")[1]) == "float" and typeof(data.get("whole")[2]) == "int", "a whole float stays a float in an array")
data.set("tree", {n: 1, s: "t", deep: {list: [1, [2, [3]]], flag: false}})
var tree = data.get("tree")
assert(tree.n == 1 and tree.s == "t" and tree.deep.list[2][2][1] == 3 and tree.deep.flag == false)
assert(typeof(tree) == "map" and typeof(tree.deep.list) == "array")

## Copies: the one read is not the store, and the one written is not either.
tree.n = 99
tree.deep.list[1] = 100
assert(data.get("tree").n == 1 and data.get("tree").deep.list[1] == 1, "a value read changed the store")
var source = [1, 2, 3]
data.set("source", source)
source[1] = 50
assert(data.get("source")[1] == 1, "a value written changed after it was kept")

## Empty ones are values, not absences; a nil in a map is no value and a nil in an array keeps its place.
data.set("e1", [])
data.set("e2", {})
assert(data.has("e1") and data.has("e2") and len(data.get("e1")) == 0 and len(data.get("e2")) == 0)
data.set("withNil", {a: 1, b: nil})
assert(data.get("withNil").a == 1 and data.get("withNil").b == nil and len(data.get("withNil")) == 1)
data.set("arrNil", [nil, 2, nil])
assert(len(data.get("arrNil")) == 3 and data.get("arrNil")[1] == nil and data.get("arrNil")[2] == 2)

## A string of any kind inside, and a key that is not an identifier.
var odd = "q" + string.fromCode(34) + string.fromCode(92) + string.fromCode(10) + "é"
data.set("odd", {[odd]: [odd], "a b": 1})
assert(data.get("odd")[odd][1] == odd and data.get("odd")["a b"] == 1)

## A class instance is kept as its fields, and what comes back is a plain map.
class Point
    func init(x, y)
        self.x = x
        self.y = y
    end
end
data.set("pt", Point(3, 4))
var pt = data.get("pt")
assert(pt.x == 3 and pt.y == 4 and typeof(pt) == "map")

## Both scopes, and a value replaced by one of another sort.
data.shared.set("sharedList", [1, 2])
assert(data.shared.get("sharedList")[2] == 2 and not data.has("sharedList"))
data.shared.delete("sharedList")
data.set("swap", [1, 2])
data.set("swap", "now a string")
assert(data.get("swap") == "now a string")
data.set("swap", {a: 1})
assert(data.get("swap").a == 1)
data.clear()
