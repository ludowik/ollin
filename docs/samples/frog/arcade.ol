## The lanes of the arcade game, as read by tools/convert_frog_data.py from the disassembly at
## https://computerarcheology.com/Arcade/Frogger/Code.html. Do not edit by hand.
##
## LANE_TILES: for each of the eleven lanes (the river from the top, the median strip, the road) the tile codes of one
## object, two per row (nil for the median strip), and LANE_PHASES how many pictures of it follow each other (the three
## poses of swimming of the turtles). TIERS: for each of the five difficulty tiers and each lane, the
## three bytes [stride, rows, count] — the gap after an object (stride / 32 tiles), its length in tiles and how many
## of them the lane holds.

const LANE_TILES = [
    [92, 93, 94, 95, 88, 89, 90, 91, 88, 89, 90, 91, 84, 85, 86, 87],
    [52, 53, 54, 55, 52, 53, 54, 55, 56, 57, 58, 59, 56, 57, 58, 59, 60, 61, 62, 63, 60, 61, 62, 63],
    [92, 93, 94, 95, 88, 89, 90, 91, 88, 89, 90, 91, 88, 89, 90, 91, 88, 89, 90, 91, 84, 85, 86, 87],
    [92, 93, 94, 95, 88, 89, 90, 91, 84, 85, 86, 87],
    [52, 53, 54, 55, 52, 53, 54, 55, 52, 53, 54, 55, 52, 53, 54, 55, 52, 53, 54, 55, 56, 57, 58, 59, 56, 57, 58, 59, 56, 57, 58, 59, 56, 57, 58, 59, 56, 57, 58, 59, 60, 61, 62, 63, 60, 61, 62, 63, 60, 61, 62, 63, 60, 61, 62, 63, 60, 61, 62, 63],
    nil,
    [172, 173, 174, 175, 168, 169, 170, 171],
    [160, 161, 162, 163],
    [48, 49, 50, 51],
    [164, 165, 166, 167],
    [80, 81, 82, 83]
]

const LANE_PHASES = [1, 3, 1, 1, 3, 1, 1, 1, 1, 1, 1]

const TIERS = [
    [[96, 8, 3], [96, 4, 4], [128, 12, 2], [128, 6, 3], [64, 6, 4], [128, 2, 4], [224, 4, 2], [96, 2, 1], [192, 2, 3], [192, 2, 3], [224, 2, 3]],
    [[96, 8, 3], [64, 4, 5], [128, 12, 1], [96, 6, 3], [192, 6, 3], [128, 2, 4], [224, 4, 3], [96, 2, 2], [224, 2, 4], [192, 2, 4], [224, 2, 4]],
    [[96, 8, 2], [128, 4, 4], [128, 12, 1], [192, 6, 3], [96, 6, 3], [128, 2, 4], [160, 4, 3], [224, 2, 2], [160, 2, 5], [224, 2, 4], [192, 2, 4]],
    [[96, 8, 2], [160, 4, 3], [128, 12, 1], [224, 6, 2], [128, 6, 3], [128, 2, 4], [128, 4, 4], [192, 2, 3], [224, 2, 4], [160, 2, 4], [224, 2, 4]],
    [[96, 8, 1], [224, 4, 3], [128, 12, 1], [160, 6, 2], [224, 6, 2], [128, 2, 4], [96, 4, 3], [160, 2, 4], [128, 2, 5], [192, 2, 4], [160, 2, 5]]
]
