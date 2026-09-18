## Classes: instantiation, method calls, inheritance and `super`.
## Measures CALL_METHOD, the walk up the prototype chain and the inline cache on field
## access. Deliberately without strings, so as to isolate the dispatch.

class Point
    func init(x, y)
        self.x = x
        self.y = y
    end
    func sum()
        return self.x + self.y
    end
end

class Point3 extends Point
    func init(x, y, z)
        super.init(x, y)
        self.z = z
    end
    func total()
        return self.sum() + self.z    ## a method inherited through the chain
    end
end

var N = 200_000
var acc = 0
var keep = []

var t0 = cpuTime()
for i = 1, N do
    var p = Point3(i, i + 1, i + 2)
    acc += p.total()
    keep[i] = p    ## kept until the end so an escape-analysis JIT cannot sink the allocation
end
var t1 = cpuTime()
acc += keep[N].total()
printf("ollin  classes {} = {}  time: {}s", N, acc, t1 - t0)
