import time
N = 100_000
t0 = time.perf_counter()
for _ in range(N):
    obj = {"x":1,"y":2,"z":3,"name":"point","value":42}
    s = obj["x"]+obj["y"]+obj["z"]+obj["value"]
    obj["x"] += 1
    obj["value"] *= 2
t1 = time.perf_counter()
print(f"python objects N={N}  time: {t1-t0:.4f}s")
