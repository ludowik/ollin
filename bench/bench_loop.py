import time
t0 = time.process_time()
s = 0
for i in range(1, 10_000_001): s += i
t1 = time.process_time()
print(f"python loop 10M = {s}  time: {t1-t0:.4f}s")
