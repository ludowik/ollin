import java.util.HashMap;

class bench_objects {
    static void run(int n) {
        for (int i = 0; i < n; i++) {
            HashMap<String, Object> obj = new HashMap<>();
            obj.put("x", 1);
            obj.put("y", 2);
            obj.put("z", 3);
            obj.put("name", "point");
            obj.put("value", 42);
            int s = (int) obj.get("x") + (int) obj.get("y") + (int) obj.get("z") + (int) obj.get("value");
            obj.put("x", (int) obj.get("x") + 1);
            obj.put("value", (int) obj.get("value") * 2);
        }
    }

    public static void main(String[] args) {
        int n = 100_000;
        for (int w = 0; w < 3; w++) run(n / 10); // warm-up, discarded
        long t0 = cpu();
        run(n);
        long t1 = cpu();
        System.out.printf("java   objects N=%d  time: %.4fs%n", n, (t1 - t0) / 1e9);
    }

    static long cpu() {
        return java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
    }
}
