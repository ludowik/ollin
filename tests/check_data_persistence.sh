#!/bin/bash
# PERSISTENCE guard of the `data` module: what one run writes, the next run must read back. The loading of the
# sidecar file happens before the script starts, so no script can test it alone — this one runs a program
# twice in a scratch directory (HOME too, so the global store of the machine is never touched).
set -u
OLLIN=${OLLIN:-./build/ollin}
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2
OLLIN=$(cd "$(dirname "$OLLIN")" && pwd)/$(basename "$OLLIN")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work"

cat > "$work/writer.ol" <<'OL'
var q = string.fromCode(34)
var bs = string.fromCode(92)
var tricky = "a" + q + "b" + bs + "c" + string.fromCode(10) + string.fromCode(13) + string.fromCode(9) + string.fromCode(1) + string.fromCode(27) + "é"
data.set("text", tricky)
data.set("int", -42)
data.set("float", 0.1)
data.set("yes", true)
data.set("no", false)
data.set("gone", 1)
data.delete("gone")
data.shared.set("text", tricky)
data.shared.set("float", 2.5)
OL

cat > "$work/reader.ol" <<'OL'
var q = string.fromCode(34)
var bs = string.fromCode(92)
var tricky = "a" + q + "b" + bs + "c" + string.fromCode(10) + string.fromCode(13) + string.fromCode(9) + string.fromCode(1) + string.fromCode(27) + "é"
assert(data.get("text") == tricky, "a string with quotes, backslash, newline, tab and control characters survives")
assert(data.get("int") == -42 and typeof(data.get("int")) == "int")
assert(data.get("float") == 0.1, "a float comes back to the last digit")
assert(data.get("yes") == true and data.get("no") == false)
assert(not data.has("gone"), "a deleted key stays deleted")
assert(len(data.keys()) == 5)
assert(data.shared.get("text") == tricky and data.shared.get("float") == 2.5)
data.clear()
data.shared.clear()
OL

fails=0
check() {
    local desc="$1"
    shift
    local out
    if out=$("$@" 2>&1); then
        echo "OK   $desc"
    else
        echo "FAIL $desc"
        echo "$out" | tail -3 | sed 's/^/     /'
        fails=$((fails + 1))
    fi
}

check "data: the first run writes" "$OLLIN" "$work/writer.ol"
# the reader has its own sidecar name: seed it from the writer's
cp "$work/writer.ol.data.json" "$work/reader.ol.data.json"
check "data: the next run reads what was written" "$OLLIN" "$work/reader.ol"
check "data: clear leaves an empty store on disk" grep -qx '{}' "$work/reader.ol.data.json"

# A damaged file is never an error: the store keeps what was read before the damage.
cat > "$work/damaged.ol" <<'OL'
assert(data.get("a") == 1)
assert(not data.has("b"))
OL
printf '{ "a" : "i1" , "b"' > "$work/damaged.ol.data.json"
check "data: a truncated file keeps the entries before the damage" "$OLLIN" "$work/damaged.ol"

cat > "$work/empty.ol" <<'OL'
assert(len(data.keys()) == 0)
OL
for blob in 'not json' '{' '{}' '{"k" "v"}' '{"k":5}' '{"k":"v\u12'; do
    printf '%s' "$blob" > "$work/empty.ol.data.json"
    check "data: the file '$blob' loads as an empty store" "$OLLIN" "$work/empty.ol"
done

[ $fails -eq 0 ]
