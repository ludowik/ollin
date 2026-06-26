class Vec2
    func init(x, y)
        self.x = x
        self.y = y
    end
    func __add(other)
        return Vec2(self.x + other.x, self.y + other.y)
    end
    func __str()
        return "Vec2(" + self.x + "," + self.y + ")"
    end
end

var v = Vec2(1, 2) + Vec2(3, 4)
print(v)
