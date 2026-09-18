import java.util.HashMap;

class bench_iter {
    static final int NA = 100_000, PA = 20;
    static final int NM = 10_000, PM = 40;

    static long run(int[] arr, HashMap<String, Integer> m, int pa, int pm) {
        long acc = 0;
        for (int p = 0; p < pa; p++) {
            for (int i = 1; i <= NA; i++) acc += arr[i];
        }
        for (int p = 0; p < pm; p++) {
            for (int v : m.values()) acc += v;
        }
        return acc;
    }

    public static void main(String[] args) {
        int[] arr = new int[NA + 1];
        for (int i = 1; i <= NA; i++) arr[i] = i;

        HashMap<String, Integer> m = new HashMap<>();
        for (int i = 1; i <= NM; i++) m.put("k" + i, i);

        run(arr, m, 3, 3); // warm-up, discarded
        long t0 = cpu();
        long acc = run(arr, m, PA, PM);
        long t1 = cpu();
        System.out.printf("java   iter %d = %d  time: %.4fs%n", (long) NA * PA + (long) NM * PM, acc,
                (t1 - t0) / 1e9);
    }

    static long cpu() {
        return java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
    }
}
