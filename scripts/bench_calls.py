import time
def id_(x): return x
t0 = time.perf_counter()
s = 0
for i in range(1, 1_000_001): s += id_(i)
t1 = time.perf_counter()
print(f"python calls 1M = {s}  time: {t1-t0:.4f}s")
