## Colours and proportions for drawing a temperature, with no screen in them so that weather_test.ol can try them.

## The colour of a temperature in degrees Celsius, as [r, g, b, a]: from cold blue through green to warm orange, by steps of a colour
## each, and held beyond the first and the last.
const TEMP_STOPS = [
    [-10, [0.45, 0.65, 1.0, 1]],
    [0, [0.45, 0.75, 1.0, 1]],
    [10, [0.5, 0.85, 0.85, 1]],
    [18, [0.78, 0.88, 0.45, 1]],
    [26, [1.0, 0.75, 0.3, 1]],
    [34, [1.0, 0.45, 0.3, 1]]
]

## The colour `mix` of the way from `a` to `b` (arrays of the same length, one number per channel).
func mixColours(a, b, mix)
    var out = []
    for k = 1, len(a) do
        out.push(a[k] + (b[k] - a[k]) * mix)
    end
    return out
end

func tempColour(temp)
    var last = len(TEMP_STOPS)
    if temp <= TEMP_STOPS[1][1] then
        return TEMP_STOPS[1][2]
    end
    for i = 2, last do
        var above = TEMP_STOPS[i]
        if temp <= above[1] then
            var below = TEMP_STOPS[i - 1]
            return mixColours(below[2], above[2], (temp - below[1]) / (above[1] - below[1]))
        end
    end
    return TEMP_STOPS[last][2]
end

## Where a temperature lies on a track that shows `lo` to `hi`: 0 at its start, 1 at its end, held inside them. A track
## of no width (every day alike) puts everything at its middle.
func onTrack(temp, lo, hi)
    if hi <= lo then
        return 0.5
    end
    return math.clamp((temp - lo) / (hi - lo), 0, 1)
end
