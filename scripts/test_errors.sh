#!/bin/bash
# Vérifie que le compilateur rejette les redéclarations et assignations illégales
OLLIN=./build/ollin
PASS=0
FAIL=0

check_error() {
    local desc="$1"
    local code="$2"
    local expected="$3"
    local actual
    actual=$(echo "$code" | $OLLIN /dev/stdin 2>&1)
    if echo "$actual" | grep -qF "$expected"; then
        echo "OK  $desc"
        PASS=$((PASS+1))
    else
        echo "FAIL $desc"
        echo "     expected: $expected"
        echo "     got:      $actual"
        FAIL=$((FAIL+1))
    fi
}

check_error "local redeclaration" \
    'var x = 1
var x = 2' \
    "local variable 'x' already declared in this scope"

check_error "local redeclaration inside function" \
    'func f()
    var y = 1
    var y = 2
end' \
    "local variable 'y' already declared in this scope"

check_error "param redeclaration via var" \
    'func f(a)
    var a = 1
end' \
    "local variable 'a' already declared in this scope"

check_error "global redeclaration" \
    'global g = 1
global g = 2' \
    "global variable 'g' already declared"

check_error "global redeclaration across functions" \
    'global h = 1
func f()
    global h = 2
end' \
    "global variable 'h' already declared"

check_error "constant sans init" \
    'constant x' \
    "must be initialized"

check_error "constant reassignment direct" \
    'constant x = 1
x = 2' \
    "cannot assign to constant 'x'"

check_error "constant compound assignment" \
    'constant x = 10
x += 1' \
    "cannot assign to constant 'x'"

check_error "constant reassignment inside function" \
    'constant k = 42
func f()
    k = 0
end' \
    "cannot assign to constant 'k'"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
