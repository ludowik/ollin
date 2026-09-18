class bench_classes {
    static class Point {
        int x, y;

        Point(int x, int y) {
            this.x = x;
            this.y = y;
        }

        int sum() {
            return x + y;
        }
    }

    static class Point3 extends Point {
        int z;

        Point3(int x, int y, int z) {
            super(x, y);
            this.z = z;
        }

        int total() {
            return sum() + z;
        }
    }

    static long run(int n, Point3[] keep) {
        long acc = 0;
        for (int i = 1; i <= n; i++) {
            Point3 p = new Point3(i, i + 1, i + 2);
            acc += p.total();
            keep[i - 1] = p; // kept until the end so an escape-analysis JIT cannot sink the allocation
        }
        acc += keep[n - 1].total();
        return acc;
    }

    public static void main(String[] args) {
        int n = 200_000;
        for (int w = 0; w < 3; w++) run(n / 10, new Point3[n / 10]); // warm-up, discarded
        Point3[] keep = new Point3[n];
        long t0 = cpu();
        long acc = run(n, keep);
        long t1 = cpu();
        System.out.printf("java   classes %d = %d  time: %.4fs%n", n, acc, (t1 - t0) / 1e9);
    }

    static long cpu() {
        return java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
    }
}
