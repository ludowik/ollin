import time
N = 1_000_000
t0 = time.perf_counter()
arr = [0] * (N+1)
for i in range(1, N+1): arr[i] = i
s = 0
for i in range(1, N+1): s += arr[i]
t1 = time.perf_counter()
print(f"python array 1M = {s}  time: {t1-t0:.4f}s")
