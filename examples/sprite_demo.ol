## sprite_demo.ol - logo rendered to a RenderTexture, animated with graphics.sprite

var g = graphics
var img = image
var m = math

## open window first (GL context required before any texture creation)
g.canvas(600, 600, "sprite demo")

## render logo into a 200x200 render texture (must come after canvas)
var gold = {r:0.831, g:0.533, b:0.102, a:1}
var bg   = {r:0.067, g:0.047, b:0, a:1}

var logo = img.create(200, 200)

img.begin_draw(logo)
    g.clear(bg)

    ## outer ring r=74 filled with gold
    g.fill(gold)
    g.noStroke()
    g.circle(100, 100, 74, 64)

    ## punch inner r=52 with background color
    g.fill(bg)
    g.circle(100, 100, 52, 64)

    ## inner rim: thin luminous circle
    g.stroke({r:1, g:0.878, b:0.376, a:0.35})
    g.strokeSize(1.5)
    g.noFill()
    g.circle(100, 100, 52, 64)

    ## 8 stepped-pyramid rays pointing outward
    g.fill(gold)
    g.noStroke()
    var ray = [
        [91,27],[109,27],[109,21],[107,21],[107,15],[105,15],
        [105,9],[103,9],[103,5],[97,5],[97,9],[95,9],
        [95,15],[93,15],[93,21],[91,21]
    ]
    var step = 0
    while step < 8 do
        g.push()
        g.translate(100, 100)
        g.rotate(step * 45)
        g.translate(-100, -100)
        g.polygon(ray)
        g.pop()
        step = step + 1
    end
img.end_draw()

## animation loop
var angle = 0.0
var scale = 1.0
var ds    = 0.005

func frame()
    g.clear({r:0.04, g:0.04, b:0.04, a:1})

    scale = scale + ds
    if scale > 1.4 then ds = -0.005 end
    if scale < 0.6 then ds =  0.005 end
    angle = angle + 1.0

    var t = (m.sin(angle * 0.03) + 1) * 0.5
    g.fill({r:1, g:0.5+t*0.5, b:t*0.3, a:1})

    g.push()
    g.translate(300, 300)
    g.rotate(angle)
    g.scale(scale)
    g.translate(-100, -100)
    g.sprite(logo, 0, 0)
    g.pop()

    ## small fixed copy top-left, no tint
    g.noFill()
    g.sprite(logo, 20, 20, 80, 80)

    g.stroke({r:1, g:1, b:1, a:0.7})
    g.strokeSize(1)
    g.draw_text("sprite demo", 10, 570, 14)
end

g.run(frame)
