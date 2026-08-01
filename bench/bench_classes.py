import time

class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y
    def sum(self):
        return self.x + self.y

class Point3(Point):
    def __init__(self, x, y, z):
        super().__init__(x, y)
        self.z = z
    def total(self):
        return self.sum() + self.z

N = 200_000
acc = 0
t0 = time.process_time()
for i in range(1, N + 1):
    p = Point3(i, i + 1, i + 2)
    acc += p.total()
t1 = time.process_time()
print(f"python classes {N} = {acc}  time: {t1-t0:.4f}s")
