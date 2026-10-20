# Shared by tests/run.sh and tests/samples.sh (sourced): the binary under test, and the report of one .ol
# program that must exit 0.

OLLIN=${OLLIN:-./build/ollin}

require_binary() {
    if [ ! -x "$OLLIN" ]; then
        echo "error: $OLLIN not found — compile it first (cmake --build build --target ollin)"
        exit 2
    fi
}

## Runs the command $2... and prints OK or FAIL under the label $1 (with the end of its output); returns 1 when it
## failed.
run_cmd() {
    local label="$1"
    shift
    local out
    out=$("$@" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        echo "OK   $label"
        return 0
    fi
    echo "FAIL $label (exit $rc)"
    echo "$out" | tail -3 | sed 's/^/     /'
    return 1
}

## The same for the .ol program $1 that must exit 0.
run_pass() {
    run_cmd "$1" "$OLLIN" "$1"
}
