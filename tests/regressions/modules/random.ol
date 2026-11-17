## The Random class: a generator of its own, the engine's Rng behind an object. The same seed gives the same numbers as
## math.seed, and nothing else draws from it.
var rnA = Random(1)
assert(rnA.randInt(1, 1000) == 567 and rnA.randInt(1, 1000) == 746 and rnA.randInt(1, 1000) == 972)
math.seed(1)
assert(math.randInt(1, 1000) == 567 and math.randInt(1, 1000) == 746 and math.randInt(1, 1000) == 972, "the same sequence as math")

## rand: [0, 1), then [0, hi], then [lo, hi], as math.rand.
math.seed(1)
var rnUnit = math.rand()
assert(Random(1).rand() == rnUnit)
var rnB = Random(9)
for rnI = 1, 200 do
    var u = rnB.rand()
    var s = rnB.rand(10)
    var w = rnB.rand(-2, 2)
    assert(u >= 0 and u < 1 and s >= 0 and s <= 10 and w >= -2 and w <= 2)
end
for rnI = 1, 200 do
    var one = rnB.randInt(5)
    assert(one >= 1 and one <= 5)
end

## Two generators of one seed agree; another seed does not; seed() starts the sequence again.
var rnC = Random(42)
var rnD = Random(42)
var rnE = Random(43)
var rnSame = true
var rnDiffers = false
for rnI = 1, 20 do
    var x = rnC.randInt(1, 1000000)
    rnSame = rnSame and x == rnD.randInt(1, 1000000)
    rnDiffers = rnDiffers or x <> rnE.randInt(1, 1000000)
end
assert(rnSame and rnDiffers)
rnC.seed(42)
rnD.seed(42)
assert(rnC.randInt(1, 1000000) == rnD.randInt(1, 1000000))

## Independent of the engine's generator, in both directions.
math.seed(5)
var rnEngine = math.rand()
math.seed(5)
var rnOwn = Random(5)
for rnI = 1, 50 do
    rnOwn.rand()
end
assert(math.rand() == rnEngine, "drawing from a Random leaves the engine generator alone")
var rnOwn2 = Random(5)
var rnOwnFirst = rnOwn2.rand()
var rnOwn3 = Random(5)
for rnI = 1, 50 do
    math.rand()
end
assert(rnOwn3.rand() == rnOwnFirst, "drawing from the engine generator leaves a Random alone")

## Random() takes a seed from the clock: the numbers are in range, whatever they are.
var rnClock = Random()
for rnI = 1, 20 do
    var v = rnClock.randInt(3, 4)
    assert(v == 3 or v == 4)
end

## A Random is an instance of its class, and the draws leave it usable as a value anywhere.
assert(instanceOf(rnA, Random) and classOf(rnA) == Random)
var rnHolder = {gen: Random(1)}
assert(rnHolder.gen.randInt(1, 1000) == 567, "a generator kept in a map goes on as any other")

## A refused call leaves the generator where it was, the engine's and a Random's alike.
math.seed(2)
var rnFirst = math.rand()
math.seed(2)
try
    math.rand("x")
catch e
end
assert(math.rand() == rnFirst)
var rnKept2 = Random(4)
var rnFirst2 = Random(4).rand()
try
    rnKept2.rand("x")
catch e
end
assert(rnKept2.rand() == rnFirst2)

## A generator already made keeps working when the script reassigns the global Random: it is recognised by what it is.
class FixedSeed extends Random
end
var rnLate = Random(1)
var rnChild = FixedSeed(1)
global Random = nil
assert(rnLate.randInt(1, 1000) == 567 and rnChild.randInt(1, 1000) == 567)
assert([1, 2, 3].shuffle(rnLate).len() == 3)
