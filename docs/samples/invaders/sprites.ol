## The LOOK of Ollin Invaders: every shape as a text pattern, the inks, and the one function that
## turns them into textures. Pure DATA and its builder — no rule of the game lives here, which is
## why it can be read on its own.
##
## The creatures are OURS: a jellyfish, a spider and a moth, drawn in the idiom of an 8x8 monochrome
## sprite. The arcade original's own creatures are its author's work and are not reproduced; only
## the MECHANICS of the game are faithful to it.
##
## Wired in from the entry file with a plain `import "sprites.ol"`: a flat import injects these
## names, so the game reads INK or calls buildSprites() as if they were written beside it.

const INK     = Color(0.90, 0.95, 1.00)
const GUN_INK = Color(0.35, 0.95, 0.45)
const SHIELD_INK = Color(0.30, 0.85, 0.40)
const TOP_INK = Color(1.00, 0.45, 0.45)
const DIM     = Color(0.55, 0.60, 0.72)

## Two frames per creature, alternating on every pass: that alternation IS the march. Three
## silhouettes of our own — a jellyfish, a spider, a moth — drawn in the idiom of an 8x8 monochrome
## sprite. The arcade original's own creatures are its author's work and are not reproduced here;
## only the MECHANICS are faithful.
const JELLY_A = ["..####..", ".######.", "########", "#.####.#", ".#.##.#.", "#..##..#", ".#....#."]
const JELLY_B = ["..####..", ".######.", "########", "#.####.#", ".#.##.#.", "..#..#..", ".#.##.#."]
const SPIDR_A = ["#......#", ".#....#.", "..####..", ".######.", "..####..", ".#.##.#.", "#.#..#.#"]
const SPIDR_B = [".#....#.", "..#..#..", "..####..", ".######.", "..####..", ".#.##.#.", "#......#"]
const MOTH_A  = ["##....##", "##.##.##", ".######.", "..####..", "..#..#..", ".#....#."]
const MOTH_B  = ["#......#", "##.##.##", "########", ".######.", "..#..#..", "#......#"]
## Our own arch: what matters is that it is a TEXTURE, eaten pixel by pixel, and not a rectangle
## that would vanish whole.
const SHIELD = [
    "......##########......",
    "....##############....",
    "...################...",
    "..##################..",
    ".####################.",
    "######################",
    "######################",
    "######################",
    "######################",
    "######################",
    "######################",
    "#########....#########",
    "########......########",
    "#######........#######",
    "######..........######",
    "#####............#####"
]
const CANNON  = ["......#......", ".....###.....", ".....###.....", "#############", "#############"]
## What is left of an alien for a fraction of a second: pieces flying apart, not a cloud.
const BURST = [
    "#..#..#..#",
    ".#.#..#.#.",
    "..#.##.#..",
    "#..####..#",
    "..#.##.#..",
    ".#.#..#.#.",
    "#..#..#..#"
]
## The bomb turns as it falls, which is how a falling thing reads at three pixels wide.
## Our own saucer: wide, flat, and lit underneath — nothing of the fleet's silhouette, since it is
## not one of them.
const UFO = [
    "....########....",
    "..############..",
    ".##############.",
    "################",
    "..##.##.##.##...",
    "...#..#..#..#...",
    "....##....##...."
]
const BOMB_A  = ["#..", ".#.", "..#", ".#."]
const BOMB_B  = ["..#", ".#.", "#..", ".#."]

## What a hit eats out of a shield. The original carved a fixed PATTERN into the shield's bitmap —
## no circle and no randomness — and the two weapons carved different ones: the cannon's shot takes a
## small bite out of the UNDERSIDE it struck, while a bomb, arriving from above, opens a wider and
## shallower crater. That is why a shield lasts a whole wave there and dissolved here: a jittered
## disc of radius three removed some thirty pixels per shot, against a dozen for these.
const SHOT_BITE = [
    "##.#",
    "####",
    ".###",
    "#.##"
]
const BOMB_BITE = [
    ".####.",
    "######",
    "##.###",
    ".####."
]

func buildSprites()
    kinds = [
        {frames: [image.fromPattern(JELLY_A), image.fromPattern(JELLY_B)], points: 30, ink: TOP_INK},
        {frames: [image.fromPattern(SPIDR_A), image.fromPattern(SPIDR_B)], points: 20, ink: INK},
        {frames: [image.fromPattern(MOTH_A), image.fromPattern(MOTH_B)], points: 10, ink: INK}
    ]
    gunImg = image.fromPattern(CANNON)
    bombImgs = [image.fromPattern(BOMB_A), image.fromPattern(BOMB_B)]
    ufoImg = image.fromPattern(UFO)
    burstImg = image.fromPattern(BURST)
end
