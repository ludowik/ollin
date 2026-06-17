import time
t0 = time.perf_counter()
s = 0
for i in range(1, 10_000_001): s += i
t1 = time.perf_counter()
print(f"python loop 10M = {s}  time: {t1-t0:.4f}s")
