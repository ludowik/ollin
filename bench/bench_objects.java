import java.util.HashMap;

class bench_objects {
    static int run(int n, HashMap<String, Object>[] keep) {
        for (int i = 1; i <= n; i++) {
            HashMap<String, Object> obj = new HashMap<>();
            obj.put("x", i);
            obj.put("y", 2);
            obj.put("z", 3);
            obj.put("name", "point");
            obj.put("value", 42);
            obj.put("x", (int) obj.get("x") + 1);
            obj.put("value", (int) obj.get("value") * 2);
            keep[i - 1] = obj; // kept until the end so an escape-analysis JIT cannot sink the allocation
        }
        HashMap<String, Object> last = keep[n - 1];
        return (int) last.get("x") + (int) last.get("value");
    }

    public static void main(String[] args) {
        int n = 100_000;
        @SuppressWarnings("unchecked")
        HashMap<String, Object>[] warmKeep = new HashMap[n / 10];
        for (int w = 0; w < 3; w++) run(n / 10, warmKeep); // warm-up, discarded
        @SuppressWarnings("unchecked")
        HashMap<String, Object>[] keep = new HashMap[n];
        long t0 = cpu();
        int total = run(n, keep);
        long t1 = cpu();
        System.out.printf("java   objects %d = %d  time: %.4fs%n", n, total, (t1 - t0) / 1e9);
    }

    static long cpu() {
        return java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
    }
}
