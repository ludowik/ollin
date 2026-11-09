## The checks and the cadence games share to keep themselves (docs/samples/lib/keep.ol).

import "keep.ol"

assert(isWhole(3, 1, 5) and not isWhole(0, 1, 5) and not isWhole(6, 1, 5) and not isWhole(2.5, 1, 5), "a whole number in its range")
assert(not isWhole("3", 1, 5) and not isWhole(nil, 1, 5) and not isWhole(true, 0, 5), "and nothing else")
assert(isNumber(2.5, 1, 5) and isNumber(2, 1, 5) and not isNumber(5.1, 1, 5) and not isNumber("2", 1, 5), "a number in its range")
assert(isOneOf("a", ["a", "b"]) and not isOneOf("c", ["a", "b"]) and not isOneOf(1, ["a", "b"]), "a text of a list")
assert(isBool(false) and not isBool(0) and not isBool(nil), "a boolean is not a number")

var positive = func(v) return isWhole(v, 1, 9) end
assert(isArrayOf([1, 2, 3], 0, 3, positive) and isArrayOf([], 0, 3, positive) and isArrayOf([1, 2], 2, 2, positive))
assert(not isArrayOf([1, 2, 3, 4], 0, 3, positive) and not isArrayOf([1], 2, 3, positive), "the number of entries is bounded both ways")
assert(not isArrayOf([1, 0], 0, 3, positive) and not isArrayOf("12", 0, 3, positive) and not isArrayOf(nil, 0, 3, positive))

var wholes = {score: [0, 100]}
var numbers = {wait: [-1, 2]}
assert(inRanges({score: 5, wait: 0.5}, wholes, numbers), "every field in its range")
assert(not inRanges({score: 5}, wholes, numbers), "a missing field")
assert(not inRanges({score: 5.5, wait: 0}, wholes, numbers), "a fraction where a whole number is wanted")
assert(not inRanges({score: 5, wait: -3}, wholes, numbers) and not inRanges({score: 101, wait: 0}, wholes, numbers), "out of range")

var written = {score: 500, wait: -9}
clampToRanges(written, wholes, numbers)
assert(written.score == 100 and written.wait == -1 and inRanges(written, wholes, numbers), "what a writer clamps is accepted")

assert(trusted(5, func(v) return v == 5 end) == 5 and trusted(6, func(v) return v == 5 end) == nil)
assert(wholeOr(7, 0, 10) == 7 and wholeOr("abc", 0, 10) == 0 and wholeOr(11, 0, 10) == 0 and wholeOr(nil, 0, 10) == 0 and wholeOr(true, 0, 10) == 0, "a stored best that is not a number is 0")

markKept("play")
assert(not keepDue(0.1, "play"), "nothing to keep a moment after a keeping")
assert(keepDue(KEEP_EVERY, "play"), "the time came")
markKept("play")
assert(keepDue(0.0, "over"), "a change of screen is kept at once")

print("keep ok")
