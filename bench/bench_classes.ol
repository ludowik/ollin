## Classes : instanciation, appel de méthode, héritage et `super`.
## Mesure CALL_METHOD, la remontée de la chaîne de prototypes et l'inline cache
## d'accès aux champs. Volontairement sans chaînes, pour isoler le dispatch.

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
        return self.sum() + self.z    ## méthode héritée via la chaîne
    end
end

var N = 200_000
var acc = 0

var t0 = cpuTime()
for i = 1, N do
    var p = Point3(i, i + 1, i + 2)
    acc += p.total()
end
var t1 = cpuTime()
printf("ollin  classes {} = {}  time: {}s", N, acc, t1 - t0)
