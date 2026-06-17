import time
def fib(n):
    if n <= 1: return n
    return fib(n-1) + fib(n-2)
t0 = time.perf_counter()
r = fib(35)
t1 = time.perf_counter()
print(f"python fib(35) = {r}  time: {t1-t0:.4f}s")
