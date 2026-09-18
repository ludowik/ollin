class bench_fib {
    static int fib(int n) {
        if (n <= 1) return n;
        return fib(n - 1) + fib(n - 2);
    }

    public static void main(String[] args) {
        for (int w = 0; w < 5; w++) fib(30); // warm-up, discarded, lets C2 compile the hot path
        long t0 = java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
        int result = fib(35);
        long t1 = java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
        System.out.printf("java   fib(35) = %d  time: %.4fs%n", result, (t1 - t0) / 1e9);
    }
}
