func makeCounter()
    var n = 0
    func inc()
        n += 1
        return n
    end
    return inc
end

var c = makeCounter()
print(c(), c(), c())
