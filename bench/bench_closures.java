import java.util.function.Function;

class bench_closures {
    static Function<Long, Long> makeAdder(long x) {
        return y -> x + y;
    }

    static long run(int n) {
        long s = 0;
        for (int i = 1; i <= n; i++) {
            Function<Long, Long> f = makeAdder(i);
            s += f.apply(1L);
        }
        return s;
    }

    public static void main(String[] args) {
        for (int w = 0; w < 3; w++) run(50_000); // warm-up, discarded
        long t0 = cpu();
        long s = run(1_000_000);
        long t1 = cpu();
        System.out.printf("java   closures 1M = %d  time: %.4fs%n", s, (t1 - t0) / 1e9);
    }

    static long cpu() {
        return java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
    }
}
