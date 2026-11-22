## The pictures of Frog (docs/samples/frog/sprites.ol) that can be told apart without a screen: how the tiles of a lane
## object are put together. The textures themselves need a graphics context.

import "sprites.ol"

## A picture split in the groups of 16 columns of its objects: each row of a lane of turtles is its turtle, repeated.
func repeats(rows, width)
    for row in rows do
        for k = 1, len(row) / width - 1 do
            if row.substr(1 + k * width, width) <> row.substr(1, width) then
                return false
            end
        end
    end
    return true
end

for lane = 0, 10 do
    if lane <> 5 then
        var rows = laneRows(lane, 0)
        assert(#rows == CELL and len(rows[1]) == laneSpec(1, lane).len, "lane {lane}: a picture as long as its objects and 16 high")
    end
end

## Three poses of swimming, each of them a group of turtles that are all alike (it was once T T T' in the second pose).
for lane = 1, 4, 3 do
    var poses = []
    for pose = 0, 2 do
        var rows = laneRows(lane, pose)
        assert(repeats(rows, CELL), "lane {lane}, pose {pose}: every turtle of the group is the same")
        poses.push(rows.join(""))
    end
    assert(poses[1] <> poses[2] and poses[2] <> poses[3] and poses[1] <> poses[3], "lane {lane}: the three poses differ")
end

## Everything else has one picture, and a log is not a group of identical pieces.
assert(not repeats(laneRows(0, 0), CELL), "a log has two ends")
print("frog sprites ok")
