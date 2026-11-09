## Colours and proportions for drawing a temperature, with no screen in them so that weather_test.ol can try them.

import "../lib/draw.ol"

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

## The top and the bottom of the sky behind each kind of weather (forecast.ol), as [r, g, b], and the sky of a page that has
## no weather yet.
const SKY = {
    clear: [[0.16, 0.45, 0.85], [0.52, 0.76, 0.96]],
    partly: [[0.25, 0.5, 0.82], [0.62, 0.78, 0.92]],
    cloud: [[0.38, 0.45, 0.55], [0.66, 0.71, 0.77]],
    fog: [[0.5, 0.55, 0.6], [0.74, 0.77, 0.8]],
    rain: [[0.17, 0.25, 0.4], [0.4, 0.5, 0.62]],
    snow: [[0.45, 0.55, 0.68], [0.82, 0.87, 0.93]],
    storm: [[0.1, 0.1, 0.22], [0.32, 0.3, 0.45]]
}
const WAITING = [[0.12, 0.2, 0.38], [0.3, 0.42, 0.6]]

const BAR_SLICES = 10

## The colours the bar of a day is drawn in, from its low to its high: the colour of each end, then BAR_SLICES between.
## They depend on the day alone, so they are made once, when the forecast arrives.
func barColours(low, high)
    var out = [tempColour(low), tempColour(high)]
    for k = 0, BAR_SLICES - 1 do
        out.push(tempColour(low + (high - low) * (k + 0.5) / BAR_SLICES))
    end
    return out
end
