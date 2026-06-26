func make_counter()
    var n = 0
    func inc()
        n += 1
        return n
    end
    return inc
end

var c = make_counter()
print(c(), c(), c())
