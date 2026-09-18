import time
N = 100_000
t0 = time.process_time()
keep = [None] * N
for i in range(1, N + 1):
    obj = {"x": i, "y": 2, "z": 3, "name": "point", "value": 42}
    obj["x"] += 1
    obj["value"] *= 2
    keep[i - 1] = obj
t1 = time.process_time()
total = keep[N - 1]["x"] + keep[N - 1]["value"]
print(f"python objects {N} = {total}  time: {t1-t0:.4f}s")
