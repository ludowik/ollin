import time
N = 200_000
nm = "ollin"
total = 0
t0 = time.process_time()
for i in range(1, N + 1):
    a = "item" + str(i) + ":" + nm
    b = f"item{i}:{nm}"
    total += len(a) + len(b)
t1 = time.process_time()
print(f"python strings {N} = {total}  time: {t1-t0:.4f}s")
