import time
W, H, MAXI = 200, 200, 50
total = 0
t0 = time.process_time()
for py in range(H):
    y0 = py * 2.0 / H - 1.0
    for px in range(W):
        x0 = px * 3.0 / W - 2.0
        zx = 0.0
        zy = 0.0
        n = 0
        while n < MAXI and zx * zx + zy * zy <= 4.0:
            tmp = zx * zx - zy * zy + x0
            zy = 2.0 * zx * zy + y0
            zx = tmp
            n += 1
        total += n
t1 = time.process_time()
print(f"python mandelbrot {W}x{H} = {total}  time: {t1-t0:.4f}s")
