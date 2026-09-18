import time

def make_adder(x):
    def adder(y):
        return x + y
    return adder

t0 = time.process_time()
s = 0
keep = [None] * 1_000_000
for i in range(1, 1_000_001):
    f = make_adder(i)
    s += f(1)
    keep[i - 1] = f  # kept until the end so an escape-analysis JIT cannot eliminate the closure
t1 = time.process_time()
s += keep[999_999](2)
print(f"python closures 1M = {s}  time: {t1-t0:.4f}s")
