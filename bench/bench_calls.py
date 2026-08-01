import time
def id_(x): return x
t0 = time.process_time()
s = 0
for i in range(1, 1_000_001): s += id_(i)
t1 = time.process_time()
print(f"python calls 1M = {s}  time: {t1-t0:.4f}s")
