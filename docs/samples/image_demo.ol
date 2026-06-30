## image.load_data — charge une image PNG EMBARQUÉE (base64), sans upload.
## (Dans le playground tu peux aussi charger tes propres fichiers via le bouton
##  « Images » puis image.load("nom.png").)

## Petit smiley 32x32 (PNG, base64) :
const SMILEY = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAm0lEQVR42u2XMQ7AIAhFnXsI597/FL2VTYcODlU+8AsmmrB9+c8EFUpZbbWrtlGEmFJhtOZmCKuxCcTbHIJgmYshQgHY5kOIv8w/IWYbznqIk0u0EMCT8A2JuUSrMp8lRrQdhNepUC1UgN41AANQb8IG8Coq9VUMBwh/iNDHyKpT/wVIUH5EqvnuiNI0pSna8hSDSZrRLMVwylw34TmhCGvoaGUAAAAASUVORK5CYII="

var W = window.width
var H = window.height
graphics.canvas(W, H, "image.load_data")

var img = image.load_data("png", SMILEY)   ## décode le base64 → texture

## quelques smileys rebondissants
global sprites = []
for i = 1, 10 do
    sprites[i] = {
        x:  math.rand_int(0, W - 64),
        y:  math.rand_int(0, H - 64),
        vx: math.rand(-140, 140),
        vy: math.rand(-140, 140),
        s:  math.rand_int(28, 72)
    }
end

func frame()
    graphics.clear(Color(0.08, 0.09, 0.14))

    for sp in sprites do
        sp.x = sp.x + sp.vx * 0.016
        sp.y = sp.y + sp.vy * 0.016
        if sp.x < 0 or sp.x > W - sp.s then sp.vx = -sp.vx end
        if sp.y < 0 or sp.y > H - sp.s then sp.vy = -sp.vy end
        image.draw(img, sp.x, sp.y, sp.s, sp.s)
    end

    ## un gros smiley central qui pulse
    var big = 110 + math.sin(time() * 2) * 28
    image.draw(img, W / 2 - big / 2, H / 2 - big / 2, big, big)

    graphics.draw_text("image.load_data : PNG embarque (base64)", 12, 12, 18, Color(0.75, 0.8, 0.9))
end

graphics.run(frame)
