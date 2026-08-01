import time
def fib(n):
    if n <= 1: return n
    return fib(n-1) + fib(n-2)
t0 = time.process_time()
r = fib(35)
t1 = time.process_time()
print(f"python fib(35) = {r}  time: {t1-t0:.4f}s")
