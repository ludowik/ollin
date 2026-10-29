## The calculator's rules: what the display and the line above it say after a run of keys.

import "engine.ol"

## The keys are written as words, and a number as one word: "2 + 10 =" presses 2, +, 1, 0 and =.
func play(keys)
    var s = calcNew()
    for word in keys.split(" ") do
        if word.number() <> nil then
            for digit in word do
                calcPress(s, digit)
            end
        else
            calcPress(s, word)
        end
    end
    return s
end

func shows(keys, want)
    var got = play(keys).display
    assert(got == want, "{keys} shows {got}, not {want}")
end

## ── Typing a number ───────────────────────────────────────────────────────────────────────────
shows("7", "7")
shows("007", "7")
shows(".", "0.")
shows(".5", "0.5")
shows("1.5 .", "1.5")
shows("12345678901", "1234567890")
shows("1.23456789012", "1.234567890")

## ── The order of the operations is the order of the keys ──────────────────────────────────────
shows("2 + 3 * 4 =", "20")
shows("2 * 3 + 4 =", "10")
shows("10 - 4 - 3 =", "3")
shows("8 / 2 / 2 =", "2")
shows("2 + 3 +", "5")
assert(play("2 + 3 +").history == "5 +")
shows("2 + * 3 =", "6")
assert(play("2 + * 3 =").history == "2 x 3 =")

## ── Equals ────────────────────────────────────────────────────────────────────────────────────
shows("5 =", "5")
shows("3 + =", "6")
shows("3 + 2 = = =", "9")
shows("2 * 3 = =", "18")
shows("2 + 3 = 7 =", "10")
shows("2 + 3 = * 4 =", "20")
assert(play("2 + 3 =").history == "2 + 3 =")
assert(play("2 + 3 = 4").history == "")

## ── Numbers that are not whole ────────────────────────────────────────────────────────────────
shows("0.1 + 0.2 =", "0.3")
shows("1 / 3 =", "0.3333333333")
shows("7 / 2 =", "3.5")
shows("3 - 5 =", "-2")
shows("0 * 5 +/- =", "0")
shows("9999999999 * 9999999999 =", "9.999999998e+19")

## ── Errors ────────────────────────────────────────────────────────────────────────────────────
var broken = play("5 / 0 =")
assert(broken.display == "Error" and broken.error)
shows("5 / 0 = 7", "7")
shows("5 / 0 = + 2 =", "2")
assert(not play("5 / 0 = C").error and play("5 / 0 = C").display == "0")
var tooLarge = "9999999999 * ".repeat(30) + "9999999999 ="      ## 1e310 does not fit a float
shows(tooLarge, "Error")

## ── The other keys ────────────────────────────────────────────────────────────────────────────
shows("5 +/-", "-5")
shows("5 +/- +/-", "5")
shows("+/- 5", "-5")
shows("5 + +/- 3 =", "2")
shows("50 %", "0.5")
shows("200 + 10 % =", "220")
shows("200 - 10 % =", "180")
shows("200 * 10 % =", "20")
shows("123 <", "12")
shows("5 <", "0")
shows("5 +/- <", "0")
shows("2 + 3 = <", "5")
shows("5 + 3 C", "0")
shows("5 + 3 C 4 =", "9")
shows("5 + 3 AC 4 =", "4")

## ── The label of the clearing key ─────────────────────────────────────────────────────────────
assert(calcClearLabel(play("")) == "AC")
assert(calcClearLabel(play("5")) == "C")
assert(calcClearLabel(play("5 +")) == "AC")
assert(calcClearLabel(play("5 + 3")) == "C")
assert(calcClearLabel(play("5 / 0 =")) == "AC")

print("calculator ok")
