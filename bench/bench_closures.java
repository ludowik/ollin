import java.util.function.Function;

class bench_closures {
    static Function<Long, Long> makeAdder(long x) {
        return y -> x + y;
    }

    @SuppressWarnings("unchecked")
    static long run(int n, Function<Long, Long>[] keep) {
        long s = 0;
        for (int i = 1; i <= n; i++) {
            Function<Long, Long> f = makeAdder(i);
            s += f.apply(1L);
            keep[i - 1] = f; // kept until the end so an escape-analysis JIT cannot eliminate it
        }
        s += keep[n - 1].apply(2L);
        return s;
    }

    public static void main(String[] args) {
        @SuppressWarnings("unchecked")
        Function<Long, Long>[] warmKeep = new Function[50_000];
        for (int w = 0; w < 3; w++) run(50_000, warmKeep); // warm-up, discarded
        @SuppressWarnings("unchecked")
        Function<Long, Long>[] keep = new Function[1_000_000];
        long t0 = cpu();
        long s = run(1_000_000, keep);
        long t1 = cpu();
        System.out.printf("java   closures 1M = %d  time: %.4fs%n", s, (t1 - t0) / 1e9);
    }

    static long cpu() {
        return java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
    }
}
