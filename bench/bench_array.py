import time
N = 1_000_000
t0 = time.process_time()
arr = [0] * (N+1)
for i in range(1, N+1): arr[i] = i
s = 0
for i in range(1, N+1): s += arr[i]
t1 = time.process_time()
print(f"python array 1M = {s}  time: {t1-t0:.4f}s")
