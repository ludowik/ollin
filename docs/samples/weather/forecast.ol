## What the weather service says, turned into something to show: the addresses to ask, the reading of the answers,
## and the words and kinds of weather behind the codes. No drawing and no network here, so that weather_test.ol
## can feed it the very texts the service sends.
##
## The service is Open-Meteo (https://open-meteo.com), free for a program like this one and asking for no key.
## It answers in JSON, and a "weather code" of the World Meteorological Organization stands for the sky.

const FORECAST_DAYS = 5

## The forecast of a place: how it is now, and the next days.
func forecastUrl(lat, lon)
    return https.query("https://api.open-meteo.com/v1/forecast", {
        latitude: lat,
        longitude: lon,
        current: "temperature_2m,weather_code,wind_speed_10m",
        daily: "weather_code,temperature_2m_max,temperature_2m_min",
        timezone: "auto",
        forecast_days: FORECAST_DAYS
    })
end

## The place of a name: its coordinates, to ask the forecast of.
func searchUrl(name)
    return https.query("https://geocoding-api.open-meteo.com/v1/search", {name: name, count: 1, language: "en", format: "json"})
end

## The kind of sky of each code, and its words. The kind picks the picture and the colours.
const SKIES = {
    [0]: {kind: "clear", text: "Clear sky"},
    [1]: {kind: "clear", text: "Mainly clear"},
    [2]: {kind: "partly", text: "Partly cloudy"},
    [3]: {kind: "cloud", text: "Overcast"},
    [45]: {kind: "fog", text: "Fog"},
    [48]: {kind: "fog", text: "Freezing fog"},
    [51]: {kind: "rain", text: "Light drizzle"},
    [53]: {kind: "rain", text: "Drizzle"},
    [55]: {kind: "rain", text: "Heavy drizzle"},
    [56]: {kind: "rain", text: "Freezing drizzle"},
    [57]: {kind: "rain", text: "Freezing drizzle"},
    [61]: {kind: "rain", text: "Light rain"},
    [63]: {kind: "rain", text: "Rain"},
    [65]: {kind: "rain", text: "Heavy rain"},
    [66]: {kind: "rain", text: "Freezing rain"},
    [67]: {kind: "rain", text: "Freezing rain"},
    [71]: {kind: "snow", text: "Light snow"},
    [73]: {kind: "snow", text: "Snow"},
    [75]: {kind: "snow", text: "Heavy snow"},
    [77]: {kind: "snow", text: "Snow grains"},
    [80]: {kind: "rain", text: "Rain showers"},
    [81]: {kind: "rain", text: "Rain showers"},
    [82]: {kind: "rain", text: "Violent showers"},
    [85]: {kind: "snow", text: "Snow showers"},
    [86]: {kind: "snow", text: "Snow showers"},
    [95]: {kind: "storm", text: "Thunderstorm"},
    [96]: {kind: "storm", text: "Thunderstorm, hail"},
    [99]: {kind: "storm", text: "Thunderstorm, hail"}
}

## A code the table does not know is shown as an overcast sky rather than as a failure.
func skyOf(code)
    return SKIES[code] or {kind: "cloud", text: "Weather code {code}"}
end

## The day of the week of a date written "2026-11-01" (Sakamoto's method): "Sun", "Mon"…
func weekday(date)
    const offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
    var y = string.number(string.substr(date, 1, 4))
    var m = string.number(string.substr(date, 6, 2))
    var d = string.number(string.substr(date, 9, 2))
    if m < 3 then
        y -= 1
    end
    var n = (y + y // 4 - y // 100 + y // 400 + offsets[m] + d) % 7
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][n + 1]
end

## ── Reading an answer ──────────────────────────────────────────────────────────────────────────────

## A list of numbers of the answer: an array, as long as `count`, of numbers.
func numbersOf(list, count)
    if typeof(list) <> "array" or len(list) < count then
        return false
    end
    for v in list do
        if typeof(v) <> "int" and typeof(v) <> "float" then
            return false
        end
    end
    return true
end

## The value of a JSON text, or nil when the text is not one (a null reads as nil too, which no answer of the service is).
func parseJson(body)
    var data = nil
    try
        data = json.parse(body)
    catch e
        return nil
    end
    return data
end

## The words the service gives when it refuses a request ("reason"), or nil when the text says nothing of the kind.
func reasonOf(body)
    var data = parseJson(body)
    if typeof(data) <> "map" or typeof(data.reason) <> "string" then
        return nil
    end
    return data.reason
end

## The weather now and over the next days, from the text of an answer of the forecast service:
##   {temp, wind, code, days: [{date, code, high, low}]}
## or nil and the reason it cannot be read.
func readForecast(body)
    var data = parseJson(body)
    if data == nil then
        return nil, "the answer is not JSON"
    end
    if typeof(data) <> "map" or typeof(data.current) <> "map" or typeof(data.daily) <> "map" then
        return nil, "the answer holds no weather"
    end
    var now = data.current
    var daily = data.daily
    if not numbersOf([now.temperature_2m, now.weather_code, now.wind_speed_10m], 3) then
        return nil, "the weather of now is missing"
    end
    var count = typeof(daily.time) == "array" and len(daily.time) or 0
    var complete = count > 0 and numbersOf(daily.weather_code, count) and numbersOf(daily.temperature_2m_max, count)
    if not complete or not numbersOf(daily.temperature_2m_min, count) then
        return nil, "the forecast of the days is missing"
    end
    var days = []
    for i = 1, count do
        days.push({date: daily.time[i], code: daily.weather_code[i], high: daily.temperature_2m_max[i], low: daily.temperature_2m_min[i]})
    end
    return {temp: now.temperature_2m, wind: now.wind_speed_10m, code: now.weather_code, days: days}
end

## The first place of an answer of the search service: {name, country, lat, lon}, or nil and the reason.
func readPlace(body)
    var data = parseJson(body)
    if data == nil then
        return nil, "the answer is not JSON"
    end
    if typeof(data) <> "map" or typeof(data.results) <> "array" or len(data.results) == 0 then
        return nil, "no such place"
    end
    var found = data.results[1]
    if typeof(found) <> "map" or typeof(found.name) <> "string" or not numbersOf([found.latitude, found.longitude], 2) then
        return nil, "the place has no position"
    end
    return {name: found.name, country: found.country or "", lat: found.latitude, lon: found.longitude}
end
