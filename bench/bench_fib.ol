func fib(n)
    if n <= 1 then
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

var t0 = cpuTime()
var result = fib(35)
var t1 = cpuTime()
printf("ollin  fib(35) = {1}  time: {2}s", result, t1 - t0)
