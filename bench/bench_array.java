class bench_array {
    static long run(int n) {
        long[] arr = new long[n + 1];
        for (int i = 1; i <= n; i++) arr[i] = i;
        long s = 0;
        for (int i = 1; i <= n; i++) s += arr[i];
        return s;
    }

    public static void main(String[] args) {
        for (int w = 0; w < 3; w++) run(100_000); // warm-up, discarded
        long t0 = cpu();
        long s = run(1_000_000);
        long t1 = cpu();
        System.out.printf("java   array 1M = %d  time: %.4fs%n", s, (t1 - t0) / 1e9);
    }

    static long cpu() {
        return java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
    }
}
