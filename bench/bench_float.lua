local W, H, MAXI = 200, 200, 50
local total = 0
local t0 = os.clock()
for py = 0, H - 1 do
    local y0 = py * 2.0 / H - 1.0
    for px = 0, W - 1 do
        local x0 = px * 3.0 / W - 2.0
        local zx, zy, n = 0.0, 0.0, 0
        while n < MAXI and zx * zx + zy * zy <= 4.0 do
            local tmp = zx * zx - zy * zy + x0
            zy = 2.0 * zx * zy + y0
            zx = tmp
            n = n + 1
        end
        total = total + n
    end
end
local t1 = os.clock()
print(string.format("lua    mandelbrot %dx%d = %d  time: %.4fs", W, H, total, t1 - t0))
