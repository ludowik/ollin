## image.loadData: an EMBEDDED PNG (base64), with no upload. (In the playground, the
## "Images" button then image.load("name.png") loads your own files.)
const SMILEY = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAm0lEQVR42u2XMQ7AIAhFnXsI597/FL2VTYcODlU+8AsmmrB9+c8EFUpZbbWrtlGEmFJhtOZmCKuxCcTbHIJgmYshQgHY5kOIv8w/IWYbznqIk0u0EMCT8A2JuUSrMp8lRrQdhNepUC1UgN41AANQb8IG8Coq9VUMBwh/iNDHyKpT/wVIUH5EqvnuiNI0pSna8hSDSZrRLMVwylw34TmhCGvoaGUAAAAASUVORK5CYII="

graphics.canvas(W, H, "image.loadData")
var img = image.loadData("png", SMILEY)

global config = {
    count:   10,
    minSize: 28,
    maxSize: 72,
    speed:   140,   ## pixels per second, either way
    pulse:   28     ## how far the big sprite breathes
}

global sprites = []
for i = 1, config.count do
    sprites[i] = {
        x:  math.randInt(0, W - config.maxSize),
        y:  math.randInt(0, H - config.maxSize),
        vx: math.rand(-config.speed, config.speed),
        vy: math.rand(-config.speed, config.speed),
        s:  math.randInt(config.minSize, config.maxSize)
    }
end

func draw()
    graphics.clear(Color(0.08, 0.09, 0.14))

    for sp in sprites do
        sp.x = sp.x + sp.vx * deltaTime
        sp.y = sp.y + sp.vy * deltaTime
        if sp.x < 0 or sp.x > W - sp.s then sp.vx = -sp.vx end
        if sp.y < 0 or sp.y > H - sp.s then sp.vy = -sp.vy end
        image.draw(img, sp.x, sp.y, sp.s, sp.s)
    end

    var big = 110 + math.sin(elapsedTime * 2) * config.pulse
    image.draw(img, W / 2 - big / 2, H / 2 - big / 2, big, big)

    graphics.stroke(Color(0.75, 0.8, 0.9))
    graphics.text("image.loadData: an embedded PNG (base64)", 12, 12)
end
