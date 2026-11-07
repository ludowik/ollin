## The reading of the weather service's answers (docs/samples/weather/forecast.ol), on texts written the way the
## service writes them. A string literal cannot hold a double quote, so the texts are written with ' and turned
## into " by q().

import "forecast.ol"

func q(t)
    return t.replace("'", string.fromCode(34))
end

## ── The addresses ──
assert(forecastUrl(48.85, 2.35) ==
       "https://api.open-meteo.com/v1/forecast?current=temperature_2m%2Cweather_code%2Cwind_speed_10m" +
       "&daily=weather_code%2Ctemperature_2m_max%2Ctemperature_2m_min&forecast_days=5&latitude=48.85" +
       "&longitude=2.35&timezone=auto")
assert(searchUrl("New York") == "https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&language=en&name=New%20York")

## ── The days of the week ──
assert(weekday("2026-11-01") == "Sun" and weekday("2026-11-02") == "Mon" and weekday("2024-02-29") == "Thu")
assert(weekday("2000-01-01") == "Sat" and weekday("1999-12-31") == "Fri" and weekday("2026-03-01") == "Sun")

## ── The skies ──
assert(skyOf(0).kind == "clear" and skyOf(2).kind == "partly" and skyOf(3).text == "Overcast")
assert(skyOf(61).kind == "rain" and skyOf(73).kind == "snow" and skyOf(95).kind == "storm" and skyOf(45).kind == "fog")
assert(skyOf(1234).kind == "cloud" and skyOf(1234).text == "Weather code 1234", "an unknown code is not a failure")
for code, sky in SKIES do
    assert(sky.text <> "" and ["clear", "partly", "cloud", "fog", "rain", "snow", "storm"].contains(sky.kind), "code {code}")
end

## ── A forecast ──
const FORECAST = q("\{'latitude':48.86,'longitude':2.36,'current':\{'time':'2026-11-01T14:00','temperature_2m':12.3," +
                   "'weather_code':61,'wind_speed_10m':14.4},'daily':\{'time':['2026-11-01','2026-11-02','2026-11-03']," +
                   "'weather_code':[61,3,0],'temperature_2m_max':[13.1,11,9.5],'temperature_2m_min':[8,6.2,4]}}")
var weather, why = readForecast(FORECAST)
assert(why == nil and weather.temp == 12.3 and weather.wind == 14.4 and weather.code == 61)
assert(len(weather.days) == 3 and weather.days[1].date == "2026-11-01" and weather.days[2].code == 3)
assert(weather.days[1].dayName == "Sun" and weather.days[2].dayName == "Mon" and weather.days[3].dayName == "Tue")
assert(weather.days[3].high == 9.5 and weather.days[3].low == 4 and weather.days[2].high == 11)

var nothing, reason = readForecast("not json")
assert(nothing == nil and reason == "the answer is not JSON")
nothing, reason = readForecast("[1]")
assert(nothing == nil and reason == "the answer holds no weather")
nothing, reason = readForecast(q("\{'current':\{'temperature_2m':1},'daily':\{}}"))
assert(nothing == nil and reason == "the weather of now is missing")
nothing, reason = readForecast(q("\{'current':\{'temperature_2m':1,'weather_code':0,'wind_speed_10m':2},'daily':\{'time':['2026-11-01'],'weather_code':[0]}}"))
assert(nothing == nil and reason == "the forecast of the days is missing")
nothing, reason = readForecast(q("\{'current':\{'temperature_2m':'cold','weather_code':0,'wind_speed_10m':2},'daily':\{}}"))
assert(nothing == nil and reason == "the weather of now is missing", "a number written as a text is not a number")
nothing, reason = readForecast(q("\{'current':\{'temperature_2m':1,'weather_code':0,'wind_speed_10m':2},'daily':\{'time':[],'weather_code':[],'temperature_2m_max':[],'temperature_2m_min':[]}}"))
assert(nothing == nil and reason == "the forecast of the days is missing", "no day at all")
nothing, reason = readForecast(q("\{'current':\{'temperature_2m':1,'weather_code':0,'wind_speed_10m':2},'daily':\{'time':['x'],'weather_code':[0],'temperature_2m_max':[1],'temperature_2m_min':[0]}}"))
assert(nothing == nil and reason == "a date of the forecast is not a date", "a day that is not a date is a refusal, not an error")
assert(weekday("2026-11-01") == "Sun" and weekday("2026-12-31") == "Thu" and weekday("2024-02-29") == "Thu", "ordinary dates")
assert(weekday("2026-02-29") == nil and weekday("2026/11/01") == nil and weekday("") == nil, "what is no date")
assert(weekday(5) == nil and weekday(nil) == nil and weekday([2026]) == nil, "not even a text")

## ── The reason a request is refused ──
assert(reasonOf(q("\{'error':true,'reason':'Latitude must be in range of -90 to 90°.'}")) == "Latitude must be in range of -90 to 90°.")
assert(reasonOf("not json") == nil and reasonOf("{}") == nil and reasonOf("5") == nil)

## ── A place ──
var place, problem = readPlace(q("\{'results':[\{'id':2988507,'name':'Paris','latitude':48.85341,'longitude':2.3488,'country':'France'}]," +
                                 "'generationtime_ms':0.5}"))
assert(problem == nil and place.name == "Paris" and place.country == "France" and place.lat == 48.85341 and place.lon == 2.3488)
place, problem = readPlace(q("\{'generationtime_ms':0.2}"))
assert(place == nil and problem == "no such place", "the service sends no results at all for an unknown name")
place, problem = readPlace(q("\{'results':[]}"))
assert(place == nil and problem == "no such place")
place, problem = readPlace(q("\{'results':[\{'name':'Nowhere'}]}"))
assert(place == nil and problem == "the place has no position")
place, problem = readPlace("\{")
assert(place == nil and problem == "the answer is not JSON")
place, problem = readPlace(q("\{'results':[\{'name':'Lone','latitude':1,'longitude':2}]}"))
assert(problem == nil and place.country == "", "a place with no country has an empty one")

print("weather forecast ok")
