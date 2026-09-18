class bench_loop {
    static long run(long n) {
        long s = 0;
        for (long i = 1; i <= n; i++) s += i;
        return s;
    }

    public static void main(String[] args) {
        for (int w = 0; w < 3; w++) run(200_000); // warm-up, discarded
        long t0 = cpu();
        long s = run(10_000_000);
        long t1 = cpu();
        System.out.printf("java   loop 10M = %d  time: %.4fs%n", s, (t1 - t0) / 1e9);
    }

    static long cpu() {
        return java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
    }
}
