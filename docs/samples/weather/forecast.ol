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
        current: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m",
        daily: "weather_code,temperature_2m_max,temperature_2m_min",
        timezone: "auto",
        forecast_days: FORECAST_DAYS
    })
end

## The place of a name: its coordinates, to ask the forecast of. The service writes the name of the place and of its
## country in `language`.
func searchUrl(name, language)
    return https.query("https://geocoding-api.open-meteo.com/v1/search", {name: name, count: 1, language: language, format: "json"})
end

## The kind of sky of each code, and the key of its words (texts.ol says them, in each language). The kind picks the
## picture and the colours.
const SKIES = {
    [0]: {kind: "clear", key: "clear"},
    [1]: {kind: "clear", key: "mainlyClear"},
    [2]: {kind: "partly", key: "partlyCloudy"},
    [3]: {kind: "cloud", key: "overcast"},
    [45]: {kind: "fog", key: "fog"},
    [48]: {kind: "fog", key: "freezingFog"},
    [51]: {kind: "rain", key: "lightDrizzle"},
    [53]: {kind: "rain", key: "drizzle"},
    [55]: {kind: "rain", key: "heavyDrizzle"},
    [56]: {kind: "rain", key: "freezingDrizzle"},
    [57]: {kind: "rain", key: "freezingDrizzle"},
    [61]: {kind: "rain", key: "lightRain"},
    [63]: {kind: "rain", key: "rain"},
    [65]: {kind: "rain", key: "heavyRain"},
    [66]: {kind: "rain", key: "freezingRain"},
    [67]: {kind: "rain", key: "freezingRain"},
    [71]: {kind: "snow", key: "lightSnow"},
    [73]: {kind: "snow", key: "snow"},
    [75]: {kind: "snow", key: "heavySnow"},
    [77]: {kind: "snow", key: "snowGrains"},
    [80]: {kind: "rain", key: "rainShowers"},
    [81]: {kind: "rain", key: "rainShowers"},
    [82]: {kind: "rain", key: "violentShowers"},
    [85]: {kind: "snow", key: "snowShowers"},
    [86]: {kind: "snow", key: "snowShowers"},
    [95]: {kind: "storm", key: "thunderstorm"},
    [96]: {kind: "storm", key: "thunderstormHail"},
    [99]: {kind: "storm", key: "thunderstormHail"}
}

## A code the table does not know is shown as an overcast sky rather than as a failure.
func skyOf(code)
    return SKIES[code] or {kind: "cloud", key: nil, code: code}
end

## The day of the week of a date written "2026-11-01" (1 Monday to 7 Sunday, as date.weekdayName counts), or nil for
## anything that is not such a date.
func weekday(text)
    if typeof(text) <> "string" then
        return nil
    end
    var parts = date.parse(text)
    return parts and parts.weekday
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
    try
        return json.parse(body)
    catch e
        return nil
    end
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
##   {temp, feels, wind, code, days: [{date, weekday, code, high, low}]}
## or nil and the reason it cannot be read, a key that texts.ol says in each language (notJson, noWeather, nowMissing,
## daysMissing, badDate). `feels`, the temperature it feels like, is nil when the answer has none. `weekday` is the day
## of the week of the date (1 Monday to 7 Sunday), worked out here once rather than at every frame.
func readForecast(body)
    var data = parseJson(body)
    if data == nil then
        return nil, "notJson"
    end
    if typeof(data) <> "map" or typeof(data.current) <> "map" or typeof(data.daily) <> "map" then
        return nil, "noWeather"
    end
    var now = data.current
    var daily = data.daily
    if not numbersOf([now.temperature_2m, now.weather_code, now.wind_speed_10m], 3) then
        return nil, "nowMissing"
    end
    var count = typeof(daily.time) == "array" and len(daily.time) or 0
    var complete = count > 0 and numbersOf(daily.weather_code, count) and numbersOf(daily.temperature_2m_max, count)
    if not complete or not numbersOf(daily.temperature_2m_min, count) then
        return nil, "daysMissing"
    end
    var days = []
    for i = 1, count do
        var day = weekday(daily.time[i])
        if day == nil then
            return nil, "badDate"
        end
        days.push({date: daily.time[i], weekday: day, code: daily.weather_code[i],
            high: daily.temperature_2m_max[i], low: daily.temperature_2m_min[i]})
    end
    var feels = nil
    if numbersOf([now.apparent_temperature], 1) then
        feels = now.apparent_temperature          ## not `and … or`: a feels-like of 0 is falsy
    end
    return {temp: now.temperature_2m, feels: feels, wind: now.wind_speed_10m, code: now.weather_code, days: days}
end

## The first place of an answer of the search service: {name, country, lat, lon}, or nil and the reason (a key of
## texts.ol: notJson, noPlace, noPosition).
func readPlace(body)
    var data = parseJson(body)
    if data == nil then
        return nil, "notJson"
    end
    if typeof(data) <> "map" or typeof(data.results) <> "array" or len(data.results) == 0 then
        return nil, "noPlace"
    end
    var found = data.results[1]
    if typeof(found) <> "map" or typeof(found.name) <> "string" or not numbersOf([found.latitude, found.longitude], 2) then
        return nil, "noPosition"
    end
    return {name: found.name, country: found.country or "", lat: found.latitude, lon: found.longitude}
end
