import time
NA, PA = 100_000, 20
NM, PM = 10_000, 40

arr = [i for i in range(1, NA + 1)]
m = {f"k{i}": i for i in range(1, NM + 1)}

acc = 0
t0 = time.process_time()
for _ in range(PA):
    for v in arr:
        acc += v
for _ in range(PM):
    for k, v in m.items():
        acc += v
t1 = time.process_time()
print(f"python iter {NA*PA + NM*PM} = {acc}  time: {t1-t0:.4f}s")
