class bench_float {
    static long run(int w, int h, int maxi) {
        long total = 0;
        for (int py = 0; py < h; py++) {
            double y0 = py * 2.0 / h - 1.0;
            for (int px = 0; px < w; px++) {
                double x0 = px * 3.0 / w - 2.0;
                double zx = 0.0, zy = 0.0;
                int n = 0;
                while (n < maxi && zx * zx + zy * zy <= 4.0) {
                    double tmp = zx * zx - zy * zy + x0;
                    zy = 2.0 * zx * zy + y0;
                    zx = tmp;
                    n++;
                }
                total += n;
            }
        }
        return total;
    }

    public static void main(String[] args) {
        for (int w = 0; w < 2; w++) run(50, 50, 50); // warm-up, discarded
        long t0 = cpu();
        long total = run(200, 200, 50);
        long t1 = cpu();
        System.out.printf("java   mandelbrot %dx%d = %d  time: %.4fs%n", 200, 200, total, (t1 - t0) / 1e9);
    }

    static long cpu() {
        return java.lang.management.ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();
    }
}
