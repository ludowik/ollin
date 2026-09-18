class bench_strings {
    static long run(int n, String nm) {
        long total = 0;
        for (int i = 1; i <= n; i++) {
            String a = "item" + i + ":" + nm;
            String b = String.format("item%d:%s", i, nm);
            total += a.length() + b.length();
        }
        return total;
    }

    public static void main(String[] args) {
        int n = 200_000;
        String nm = "ollin";
        for (int w = 0; w < 3; w++) run(n / 10, nm); // warm-up, discarded
        long t0 = cpu();
        long total = run(n, nm);
        long t1 = cpu();
        System.out.printf("java   strings %d = %d  time: %.4fs%n", n, total, (t1 - t0) / 1e9);
    }

    static long cpu() {
        return java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
    }
}
