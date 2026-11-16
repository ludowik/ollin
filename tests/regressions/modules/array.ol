## Regression tests — The array pseudo-methods and the native callbacks that run Ollin code.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/array.ol — it must finish without error.

## array pseudo-methods served by array_module, with no chain of strcmp in GET_INDEX: an unknown
## field must stay an ERROR, not nil.
var arr_err = false
try
    var bad_field = [1, 2].zzz
    print(bad_field)
catch e
    arr_err = true
end
assert(arr_err)
## for..in walks a SNAPSHOT of the array (ArrayIterator copies it at MAKE_ITER): a delete during
## the loop does not skip or repeat elements, but the deleted index still shows up on later turns
## since the loop never re-reads the live array.
var snap_seen = []
var snap_arr = [10, 20, 30, 40, 50]
for si, sv in snap_arr do
    snap_seen.push(sv)
    if si == 2 then
        snap_arr.delete(2)
    end
end
assert(snap_seen.join(",") == "10,20,30,40,50")   ## unaffected by the delete
assert(snap_arr.len() == 4)                       ## the live array DID shrink
## …and that snapshot is exactly why arr.delete(i) is NOT safe for "remove every dead one" inside
## the same loop: i is a position in the frozen snapshot, and it drifts past the live array's
## shrinking bounds once more than one element has already been removed.
var drift_arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
var drift_dead = [true, false, true, false, true, false, true, false, true, false, true]
var drift_err = false
try
    for di, dv in drift_arr do
        if drift_dead[di] then
            drift_arr.delete(di)
        end
    end
catch e
    drift_err = true
end
assert(drift_err)      ## "array index out of bounds" once the drift outruns the live array
## arr.remove(v) has no such drift: it looks up v by IDENTITY in the LIVE array (ValueEqual, never
## a script's __eq), wherever it now sits, so removing several objects in the same for..in loop —
## the actual use case a snapshot-based iterator invites — works regardless of how many turns
## already shrank the array.
class RmObj
    func init(n)
        self.n = n
    end
end
var rm_arr = []
for ri = 1, 11 do
    rm_arr.push(RmObj(ri))
end
for ri, ro in rm_arr do
    if ro.n % 2 == 1 then
        assert(rm_arr.remove(ro) == ro)    ## returns the removed object itself
    end
end
assert(rm_arr.len() == 5)
assert(rm_arr[1].n == 2 and rm_arr[5].n == 10)
assert(rm_arr.remove(RmObj(2)) == nil)     ## a DIFFERENT instance with the same field: no identity match
## indexOf and contains share the same identity rule as remove — never a script's __eq — and
## indexOf is 1-based, like every other array index.
var idx_arr = [RmObj(2), RmObj(4), RmObj(6)]
assert(idx_arr.indexOf(idx_arr[2]) == 2)
assert(idx_arr.indexOf(RmObj(4)) == nil)       ## a different instance, same field: no match
assert(idx_arr.contains(idx_arr[3]))
assert(not idx_arr.contains(RmObj(6)))
assert([1, 2, 3].indexOf(2.0) == 2 and [1, 2, 3].contains(2.0))   ## numbers: value equality, INTEGER(2) == FLOAT(2.0)
## sorting: an explicit comparator, and an order by type rank without one
var srt = [1, 2, 3].sort(func(x, y) return x > y end)
assert(srt[1] == 3)
assert(srt[3] == 1)
var srt_mix = [3, "a", nil, 1].sort()
assert(srt_mix[1] == nil)      ## nil < numbers < strings
assert(srt_mix[2] == 1)
assert(srt_mix[4] == "a")
## insert(v) is push, insert(i, v) is positional (1-based)
var ins = [1, 2]
ins.insert(9)
assert(ins[3] == 9)
ins.insert(1, 7)
assert(ins[1] == 7)

## A native member that calls back into Ollin must not keep a REFERENCE into the register file:
## the call can grow it, which reallocates it. map/filter/reduce/sort held `ctx.args[0]` and
## `ctx.args[1]` by reference, so a callback recursing deep enough made them read freed memory —
## map gave back nil for every element instead of the returned values.
func rq_deep(n)
    if n <= 0 then
        return 0
    end
    return rq_deep(n - 1)
end
var rq_src = [1, 2, 3]
var rq_map = rq_src.map(func(v) rq_deep(300) return v * 10 end)
assert(rq_map[1] == 10)
assert(rq_map[2] == 20)
assert(rq_map[3] == 30)
assert(len(rq_src.filter(func(v) rq_deep(300) return v > 1 end)) == 2)
assert(rq_src.reduce(func(a, v) rq_deep(300) return a + v end, 0) == 6)
var rq_sorted = [3, 1, 2]
rq_sorted.sort(func(a, b) rq_deep(300) return a < b end)
assert(rq_sorted[1] == 1)
assert(rq_sorted[3] == 3)

## join names every kind of value the way print does, a class, a map, a range and a function included
class JoinCls
end
assert(["x", JoinCls, {a: 1}, [1;3], print, func() end, 4 / 2].join(",") == "x,\{class},\{map},\{range},\{function},\{function},2")

## a native function works as the callback of the higher-order methods
assert([1.5, 2.5].map(math.floor)[2] == 2)
assert([3, 9, 4].reduce(math.max, 0) == 9)

## A method called without its argument names itself in the refusal.
var arrNoArg = nil
try
    var r = [1, 2].contains()
catch e
    arrNoArg = e
end
assert(arrNoArg == "array.contains: expected (array, value)")

## delete takes an integer index: anything else removes nothing and answers nil.
var arrKeep = [1, 2]
assert(arrKeep.delete("a") == nil)
assert(#arrKeep == 2)

## Without a comparator the order is nil, numbers, strings, then every other value, which keeps the
## order it had among itself (the sort is stable). Strings compare as text.
var arrWords = ["b", "a", "c"]
arrWords.sort()
assert(arrWords[1] == "a" and arrWords[2] == "b" and arrWords[3] == "c")
var arrKinds = [{k: 1}, "z", 3, nil, 1.5, "a", {k: 2}]
arrKinds.sort()
assert(arrKinds[1] == nil and arrKinds[2] == 1.5 and arrKinds[3] == 3)
assert(arrKinds[4] == "a" and arrKinds[5] == "z")
assert(arrKinds[6].k == 1 and arrKinds[7].k == 2)

## copy is a SHALLOW copy: a new array with the same elements, in the same order, the nil ones included.
var cpSrc = [1, nil, "x", 4]
var cpDup = cpSrc.copy()
assert(#cpDup == 4 and cpDup[1] == 1 and cpDup[2] == nil and cpDup[3] == "x" and cpDup[4] == 4)
cpDup[1] = 99
cpDup.push(5)
assert(cpSrc[1] == 1 and #cpSrc == 4)       ## changing the copy leaves the original alone
cpSrc.pop()
assert(#cpDup == 5)                         ## and the other way round
assert([].copy().len() == 0)
## what the elements hold is shared, as anywhere else in the language
var cpInner = {n: 1}
var cpNest = [cpInner, [1, 2]]
var cpNestDup = cpNest.copy()
cpInner.n = 2
cpNest[2].push(3)
assert(cpNestDup[1].n == 2 and #cpNestDup[2] == 3)
## the use the tutorial names: sort a copy to keep the order that was
var cpOrder = [3, 1, 2]
var cpSorted = cpOrder.copy().sort()
assert(cpOrder[1] == 3 and cpSorted[1] == 1)

## repeat gives the elements of the array `count` times over, as a NEW array.
assert([0].repeat(5).join(",") == "0,0,0,0,0")
assert([1, 2].repeat(3).join(",") == "1,2,1,2,1,2")
var rpBase = [7, 8]
rpBase.repeat(2).push(9)
assert(#rpBase == 2)                              ## the array repeated is left alone
assert([1, 2].repeat(1).len() == 2 and [1].repeat(0).len() == 0 and [1].repeat(-3).len() == 0 and [].repeat(4).len() == 0)
assert([nil].repeat(3).len() == 3)                ## a nil is an element like another
## the elements are SHARED, as everywhere in the language: three times the same array
var rpRows = [[]].repeat(3)
rpRows[1].push("x")
assert(#rpRows[2] == 1 and #rpRows[3] == 1)
## whereas a new call makes a new array, which is how a grid of distinct rows is built
var rpA = [0].repeat(2)
var rpB = [0].repeat(2)
rpA[1] = 5
assert(rpB[1] == 0)
## the ceiling is the size of an array (the refusal past it is in test_errors.sh)
assert([1].repeat(16777216).len() == 16777216)

## concat: the elements of the receiver, then those of each array given, in a NEW array.
var ccBase = [1, 2]
assert(ccBase.concat([3], [4, 5]).join(",") == "1,2,3,4,5")
assert(ccBase.concat().join(",") == "1,2" and ccBase.concat([]).len() == 2 and [].concat([], []).len() == 0)
ccBase.concat([3]).push(9)
assert(#ccBase == 2)                              ## the array and its arguments are left alone
assert(ccBase.concat(ccBase).join(",") == "1,2,1,2")
var ccInner = [[]]
var ccBoth = ccInner.concat(ccInner)
ccBoth[1].push("x")
assert(#ccInner[1] == 1 and #ccBoth[2] == 1)      ## the elements are shared
assert([nil].concat([nil]).len() == 2)

## The `array` module is the free-function form of every method: the same functions, the array first.
assert(typeof(array) == "module")
assert(array.len(ccBase) == 2 and array.concat(ccBase, [7]).join(",") == "1,2,7")
assert(array.copy(ccBase).len() == 2 and array.repeat([0, 1], 2).join(",") == "0,1,0,1")
var arrFree = [3, 1, 2]
array.push(arrFree, 0)
assert(array.indexOf(arrFree, 0) == 4 and array.contains(arrFree, 3) and array.sort(arrFree)[1] == 0)
assert(array.map([1, 2], func(v) return v * 2 end).join(",") == "2,4" and array.join([1, 2], "-") == "1-2")
## a local may take the name, as it may take `string` or `map`
func arrShadow(array)
    return array.len()
end
assert(arrShadow([1, 2, 3]) == 3)
