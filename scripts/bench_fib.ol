func fib(n)
    if n <= 1 then
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

var t0 = time()
var result = fib(35)
var t1 = time()
printf("ollin  fib(35) = {0}  time: {1}s", result, t1 - t0)
