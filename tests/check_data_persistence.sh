#!/bin/bash
# PERSISTENCE guard of the `data` module: what one run writes, the next run must read back. The loading of the
# sidecar file happens before the script starts, so no script can test it alone — this one runs a program
# twice in a scratch directory (HOME too, so the global store of the machine is never touched).
set -u
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2
. tests/lib.sh
require_binary

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work"

# Both runs build the same awkward string: quotes, backslash, newline, carriage return, tab, control characters, UTF-8.
cat > "$work/prelude.ol" <<'OL'
var tricky = "a" + string.fromCode(34) + "b" + string.fromCode(92) + "c" + string.fromCode(10) + string.fromCode(13) + string.fromCode(9) + string.fromCode(1) + string.fromCode(27) + "é"
OL

cat > "$work/writer.body" <<'OL'
data.set("text", tricky)
data.set("int", -42)
data.set("float", 0.1)
data.set("yes", true)
data.set("no", false)
data.set("gone", 1)
data.delete("gone")
data.shared.set("text", tricky)
data.shared.set("float", 2.5)
data.set("list", [1, 2.5, tricky, true, nil, [3, 4]])
data.set("tree", {n: 1, s: tricky, deep: {l: [1, 2], flag: false}})
data.shared.set("shared tree", {a: [1, {b: 2}]})
OL

cat > "$work/reader.body" <<'OL'
assert(data.get("text") == tricky, "a string with quotes, backslash, newline, tab and control characters survives")
assert(data.get("int") == -42 and typeof(data.get("int")) == "int")
assert(data.get("float") == 0.1, "a float comes back to the last digit")
assert(data.get("yes") == true and data.get("no") == false)
assert(not data.has("gone"), "a deleted key stays deleted")
assert(len(data.keys()) == 7)
assert(data.shared.get("text") == tricky and data.shared.get("float") == 2.5)
var list = data.get("list")
assert(len(list) == 6 and list[1] == 1 and typeof(list[1]) == "int" and list[2] == 2.5 and list[3] == tricky)
assert(list[4] == true and list[5] == nil and list[6][2] == 4, "an array comes back whole from the file")
var tree = data.get("tree")
assert(tree.n == 1 and tree.s == tricky and tree.deep.l[2] == 2 and tree.deep.flag == false)
assert(data.shared.get("shared tree").a[2].b == 2)
data.clear()
data.shared.clear()
OL

# The sidecar is named after the program, so both runs are the same file: prog.ol.
fails=0
cat "$work/prelude.ol" "$work/writer.body" > "$work/prog.ol"
run_cmd "data: the first run writes" "$OLLIN" "$work/prog.ol" || fails=$((fails + 1))
cat "$work/prelude.ol" "$work/reader.body" > "$work/prog.ol"
run_cmd "data: the next run reads what was written" "$OLLIN" "$work/prog.ol" || fails=$((fails + 1))
run_cmd "data: clear leaves an empty store on disk" grep -qx '{}' "$work/prog.ol.data.json" || fails=$((fails + 1))

# A value that did not change is not written again: the file keeps its date. Its date is set far back; a run that
# sets the same values leaves it there, and a run that sets another value moves it.
cat > "$work/same.ol" <<'OL'
data.set("n", 1)
data.set("list", [1, {a: 2}])
data.set("gone", nil)
OL
run_cmd "data: a first run writes the file" "$OLLIN" "$work/same.ol" || fails=$((fails + 1))
touch -d '2001-01-01 00:00:00' "$work/same.ol.data.json"
old=$(stat -c %Y "$work/same.ol.data.json")
run_cmd "data: a run that sets the same values" "$OLLIN" "$work/same.ol" || fails=$((fails + 1))
if [ "$(stat -c %Y "$work/same.ol.data.json")" -eq "$old" ]; then
    echo "OK   data: a value that did not change is not written again"
else
    echo "FAIL data: the file was written again for values that had not changed"
    fails=$((fails + 1))
fi
cat > "$work/other.ol" <<'OL'
data.set("list", [1, {a: 3}])
OL
cp "$work/other.ol" "$work/same2.ol"
cp "$work/same.ol.data.json" "$work/same2.ol.data.json"
touch -d '2001-01-01 00:00:00' "$work/same2.ol.data.json"
run_cmd "data: a run that sets another value" "$OLLIN" "$work/same2.ol" || fails=$((fails + 1))
if [ "$(stat -c %Y "$work/same2.ol.data.json")" -gt "$old" ]; then
    echo "OK   data: a value that changed is written"
else
    echo "FAIL data: a changed value was not written"
    fails=$((fails + 1))
fi

# A damaged file is never an error: the store keeps what was read before the damage.
cat > "$work/damaged.ol" <<'OL'
assert(data.get("a") == 1)
assert(not data.has("b"))
OL
printf '{ "a" : "i1" , "b"' > "$work/damaged.ol.data.json"
run_cmd "data: a truncated file keeps the entries before the damage" "$OLLIN" "$work/damaged.ol" || fails=$((fails + 1))

cat > "$work/empty.ol" <<'OL'
assert(len(data.keys()) == 0)
OL
# An entry whose value is empty is read as a nil that is still there: the key exists.
cat > "$work/nilvalue.ol" <<'OL'
assert(data.has("k"))
assert(data.get("k") == nil)
OL
printf '{"k":""}' > "$work/nilvalue.ol.data.json"
run_cmd "data: an empty value loads as a nil entry" "$OLLIN" "$work/nilvalue.ol" || fails=$((fails + 1))

for blob in 'not json' '{' '{}' '{"k" "v"}' '{"k":5}' '{k:1}' '{"k":"v' '{"k":"v\' '{"k":"v\u12'; do
    printf '%s' "$blob" > "$work/empty.ol.data.json"
    run_cmd "data: the file '$blob' loads as an empty store" "$OLLIN" "$work/empty.ol" || fails=$((fails + 1))
done

[ $fails -eq 0 ]
