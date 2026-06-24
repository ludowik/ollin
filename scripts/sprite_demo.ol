// sprite_demo.ol — logo rendered to a RenderTexture, animated with graphics.sprite

var g = graphics
var img = image
var m = math

// ── render logo into a 200×200 render texture ─────────────────────────────────

var logo = img.create(200, 200)

img.begin(logo)
    g.clear({r:0.067, g:0.047, b:0, a:1})  // #110C00 background

    // fill color: gold gradient approximated as solid #D4881A
    var gold = {r:0.831, g:0.533, b:0.102, a:1}

    // Outer ring (r=74), inner ring (r=52) — draw outer filled then punch inner with background
    g.fill(gold)
    g.stroke()
    g.circle(100, 100, 74, 64)

    g.fill({r:0.067, g:0.047, b:0, a:1})
    g.circle(100, 100, 52, 64)

    // Inner rim: thin luminous circle at r=52
    g.stroke({r:1, g:0.878, b:0.376, a:0.35})
    g.strokeSize(1.5)
    g.fill()
    g.circle(100, 100, 52, 64)

    // 8 stepped-pyramid rays (pointing outward from ring top)
    // Steps: base w=18 at y=27, w=14 at y=21, w=10 at y=15, w=6 at y=9, tip w=6 at y=5
    g.fill(gold)
    g.stroke()
    var ray = [
        [91,27],[109,27],[109,21],[107,21],[107,15],[105,15],
        [105,9],[103,9],[103,5],[97,5],[97,9],[95,9],
        [95,15],[93,15],[93,21],[91,21]
    ]
    var step = 0
    while step < 8 {
        g.push()
        g.translate(100, 100)
        g.rotate(step * 45)
        g.translate(-100, -100)
        g.polygon(ray)
        g.pop()
        step = step + 1
    }
img.end()

// ── window & animation loop ───────────────────────────────────────────────────

g.canvas(600, 600, "sprite demo")

var angle = 0.0
var scale = 1.0
var ds    = 0.005

g.run(var() {
    g.clear({r:0.04, g:0.04, b:0.04, a:1})

    // bouncing scale
    scale = scale + ds
    if scale > 1.4 { ds = -0.005 }
    if scale < 0.6 { ds =  0.005 }
    angle = angle + 1.0

    // draw logo centred, rotating and pulsing
    // tint cycles through warm gold hue via fill
    var t = (m.sin(angle * 0.03) + 1) * 0.5
    g.fill({r:1, g:0.5+t*0.5, b:t*0.3, a:1})

    g.push()
        g.translate(300, 300)
        g.rotate(angle)
        g.scale(scale)
        g.translate(-100, -100)
        g.sprite(logo, 0, 0)
    g.pop()

    // second logo: fixed, smaller, top-left corner, no tint
    g.fill()
    g.sprite(logo, 20, 20, 80, 80)

    g.stroke({r:1, g:1, b:1, a:0.7})
    g.strokeSize(1)
    g.draw_text("sprite demo  FPS: " + g.fps(), 10, 570, 14)
})
