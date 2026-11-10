## The reading of the weather service's answers (docs/samples/weather/forecast.ol), on texts written the way the
## service writes them. A string literal cannot hold a double quote, so the texts are written with ' and turned
## into " by q().

import "forecast.ol"
import "pager.ol"
import "scale.ol"
import "texts.ol"
import "../lib/i18n_testlib.ol"

func q(t)
    return t.replace("'", string.fromCode(34))
end

## ── The addresses ──
assert(forecastUrl(48.85, 2.35) ==
       "https://api.open-meteo.com/v1/forecast?current=temperature_2m%2Capparent_temperature%2Cweather_code%2Cwind_speed_10m" +
       "&daily=weather_code%2Ctemperature_2m_max%2Ctemperature_2m_min&forecast_days=5&latitude=48.85" +
       "&longitude=2.35&timezone=auto")
assert(searchUrl("New York", "en") == "https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&language=en&name=New%20York")
assert(searchUrl("Londres", "fr") == "https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&language=fr&name=Londres")

## ── The days of the week ──
assert(weekday("2026-11-01") == 7 and weekday("2026-11-02") == 1 and weekday("2024-02-29") == 4)
assert(weekday("2000-01-01") == 6 and weekday("1999-12-31") == 5 and weekday("2026-03-01") == 7)

## ── The skies ──
assert(skyOf(0).kind == "clear" and skyOf(2).kind == "partly" and skyOf(3).key == "overcast")
assert(skyOf(61).kind == "rain" and skyOf(73).kind == "snow" and skyOf(95).kind == "storm" and skyOf(45).kind == "fog")
assert(skyOf(1234).kind == "cloud" and skyOf(1234).key == nil and skyOf(1234).code == 1234, "an unknown code is not a failure")
for code, sky in SKIES do
    assert(sky.key <> nil and ["clear", "partly", "cloud", "fog", "rain", "snow", "storm"].contains(sky.kind), "code {code}")
end

## ── A forecast ──
const FORECAST = q("\{'latitude':48.86,'longitude':2.36,'current':\{'time':'2026-11-01T14:00','temperature_2m':12.3," +
                   "'weather_code':61,'wind_speed_10m':14.4},'daily':\{'time':['2026-11-01','2026-11-02','2026-11-03']," +
                   "'weather_code':[61,3,0],'temperature_2m_max':[13.1,11,9.5],'temperature_2m_min':[8,6.2,4]}}")
var weather, why = readForecast(FORECAST)
assert(why == nil and weather.temp == 12.3 and weather.wind == 14.4 and weather.code == 61)
assert(len(weather.days) == 3 and weather.days[1].date == "2026-11-01" and weather.days[2].code == 3)
assert(weather.days[1].weekday == 7 and weather.days[2].weekday == 1 and weather.days[3].weekday == 2)
assert(weather.days[3].high == 9.5 and weather.days[3].low == 4 and weather.days[2].high == 11)

assert(weather.feels == nil, "an answer with no apparent temperature has no feels-like")
const WITH_FEELS = q("\{'current':\{'temperature_2m':1,'apparent_temperature':0,'weather_code':3,'wind_speed_10m':2},'daily':\{'time':['2026-11-01']," +
                     "'weather_code':[3],'temperature_2m_max':[2],'temperature_2m_min':[0]}}")
weather = readForecast(WITH_FEELS)
assert(weather.feels == 0 and weather.temp == 1, "a feels-like of 0 degrees is read, not dropped")

var nothing, reason = readForecast("not json")
assert(nothing == nil and reason == "notJson")
nothing, reason = readForecast("[1]")
assert(nothing == nil and reason == "noWeather")
nothing, reason = readForecast(q("\{'current':\{'temperature_2m':1},'daily':\{}}"))
assert(nothing == nil and reason == "nowMissing")
nothing, reason = readForecast(q("\{'current':\{'temperature_2m':1,'weather_code':0,'wind_speed_10m':2},'daily':\{'time':['2026-11-01'],'weather_code':[0]}}"))
assert(nothing == nil and reason == "daysMissing")
nothing, reason = readForecast(q("\{'current':\{'temperature_2m':'cold','weather_code':0,'wind_speed_10m':2},'daily':\{}}"))
assert(nothing == nil and reason == "nowMissing", "a number written as a text is not a number")
nothing, reason = readForecast(q("\{'current':\{'temperature_2m':1,'weather_code':0,'wind_speed_10m':2},'daily':\{'time':[],'weather_code':[],'temperature_2m_max':[],'temperature_2m_min':[]}}"))
assert(nothing == nil and reason == "daysMissing", "no day at all")
nothing, reason = readForecast(q("\{'current':\{'temperature_2m':1,'weather_code':0,'wind_speed_10m':2},'daily':\{'time':['x'],'weather_code':[0],'temperature_2m_max':[1],'temperature_2m_min':[0]}}"))
assert(nothing == nil and reason == "badDate", "a day that is not a date is a refusal, not an error")
assert(weekday("2026-11-01") == 7 and weekday("2026-12-31") == 4 and weekday("2024-02-29") == 4, "ordinary dates: 1 Monday to 7 Sunday")
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
assert(place == nil and problem == "noPlace", "the service sends no results at all for an unknown name")
place, problem = readPlace(q("\{'results':[]}"))
assert(place == nil and problem == "noPlace")
place, problem = readPlace(q("\{'results':[\{'name':'Nowhere'}]}"))
assert(place == nil and problem == "noPosition")
place, problem = readPlace("\{")
assert(place == nil and problem == "notJson")
place, problem = readPlace(q("\{'results':[\{'name':'Lone','latitude':1,'longitude':2}]}"))
assert(problem == nil and place.country == "", "a place with no country has an empty one")

## ── The texts ──
## Both languages say everything, in texts of the same kind: a key missing from one would show on the screen as nothing.
checkLanguages()
assert(i18n.languages[1] == "fr", "French is the default language")
for code in LANGUAGES do
    var table = TEXTS[code]
    for key, names in table.cities do
        assert(len(names) == 2 and names[1] <> "" and names[2] <> "", "{code}: {key} wants a name and a country")
    end
    ## the texts that take a figure or a name say it
    assert(table.forecastTitle(5).find("5") <> nil and table.lookingFor("Nîmes").find("Nîmes") <> nil)
    assert(table.noPlace("Nîmes").find("Nîmes") <> nil and table.answered(503).find("503") <> nil)
    assert(table.highLow(18, 10).find("18") <> nil and table.highLow(18, 10).find("10") <> nil)
    assert(table.cannotRead("x").find("x") <> nil and table.skyUnknown(1234).find("1234") <> nil)
end
## every sky of the table, and every reason forecast.ol gives, has its words in every language
for code, sky in SKIES do
    for lang in LANGUAGES do
        assert(TEXTS[lang].sky[sky.key] <> nil, "{lang} has no words for the sky {sky.key}")
    end
end
for lang in LANGUAGES do
    for key in ["notJson", "noWeather", "nowMissing", "daysMissing", "badDate", "noPlace", "noPosition"] do
        assert(TEXTS[lang].reasons[key] <> nil, "{lang} has no words for the reason {key}")
    end
end
assert(setLanguage("en") and skyText(skyOf(3)) == "Overcast" and skyText(skyOf(1234)) == "Weather code 1234")
assert(reasonText("notJson") == "the answer is not JSON" and reasonText("unheard of") == "unheard of")
assert(setLanguage("fr") and skyText(skyOf(3)) == "Couvert" and skyText(skyOf(61)) == "Pluie légère")

print("weather forecast ok")

## ── The pages ──
assert(dragPos(2, 100, 100, 400, 5) == 2, "a finger that has not moved leaves the pages where they were")
assert(dragPos(2, 300, 100, 400, 5) == 2.5, "dragging left by half a screen shows half of the next page")
assert(dragPos(2, 100, 300, 400, 5) == 1.5)
assert(dragPos(1, 100, 4000, 400, 5) == 1 - EDGE, "the first page gives a little, then holds")
assert(dragPos(5, 4000, 100, 400, 5) == 5 + EDGE)
assert(pageAfterDrag(2.2, 0, 2, 5) == 2 and pageAfterDrag(2.6, 0, 2, 5) == 3, "a slow release goes to the nearest page")
assert(pageAfterDrag(2.2, 3, 2, 5) == 3, "a flick carries it on to the next one")
assert(pageAfterDrag(2.8, -3, 2, 5) == 2, "and a flick back carries it back")
assert(pageAfterDrag(2.9, 40, 2, 5) == 3 and pageAfterDrag(1.1, -40, 2, 5) == 1, "never more than a page at once")
assert(pageAfterDrag(0.8, -5, 1, 5) == 1 and pageAfterDrag(5.3, 5, 5, 5) == 5, "the ends hold")
var pos, speed = slide(1, 0, 3, 0.05)
assert(pos > 1 and pos < 3 and speed > 0, "a slide from rest sets off towards the page")
var stiffer = slide(1, 0, 3, 0.016, FOLLOW)
assert(stiffer > slide(1, 0, 3, 0.016) and stiffer < 3, "a stiffer spring closes more of the gap in a frame, and still does not pass it")
pos, speed = slide(2.9996, 0, 3, 0.016)
assert(pos == 3 and speed == 0, "and ends exactly on it")
assert(math.abs(launch(1.4, 12, 2) - 0.6 * STIFF) < 1e-9 and launch(1.4, 0.5, 2) == 0.5, "the speed of the finger is kept, up to what lands on the page")
assert(math.abs(launch(1.6, -12, 1) + 0.6 * STIFF) < 1e-9 and launch(1.6, 0.5, 1) == 0.5, "a finger going away from the page is not cut")

## A slide launched by launch() reaches the page and never goes past it, at any speed and any length of frame, and a
## speed that carries on keeps the pages moving the way they were (no jump at the release).
for dt in [1 / 120, 1 / 60, 1 / 20] do
    for start in [1.3, 1.5, 1.8] do
        for finger in [0, 0.5, 3, 12] do
            pos, speed = start, launch(start, finger, 2)
            var past = 0
            for i = 1, 400 do
                pos, speed = slide(pos, speed, 2, dt)
                past = math.max(past, pos - 2)
            end
            assert(past <= 1e-9 and pos == 2, "dt {dt} from {start} at {finger}: past by {past}, ends at {pos}")
        end
    end
end
pos, speed = slide(1.4, 2, 2, 1 / 60)
assert(pos > 1.4 + 2 / 60 * 0.9 and speed > 1.5, "the first frame goes on at about the speed of the finger")

var from, to, mix = skyBetween(2.25, 5)
assert(from == 2 and to == 3 and mix == 0.25, "a quarter of the way from page 2 to page 3")
from, to, mix = skyBetween(3, 5)
assert(from == 3 and to == 4 and mix == 0, "on a page, only its own sky")
from, to, mix = skyBetween(0.7, 5)
assert(from == 1 and to == 2 and mix == 0, "pulled past the first page, its sky holds")
from, to, mix = skyBetween(5.3, 5)
assert(from == 5 and to == 5, "pulled past the last page, its sky holds")

## The speed of a drag is read from its last tenth of a second.
var trail = [[0, 1]]
assert(math.abs(track(trail, 0.016, 1.04) - 2.5) < 1e-9, "0.04 of a page in 16 ms is 2.5 pages a second")
assert(math.abs(track(trail, 0.032, 1.08) - 2.5) < 1e-9, "and it goes on at that speed")
var still = 0
for i = 3, 12 do
    still = track(trail, i * 0.016, 1.08)
end
assert(still == 0 and len(trail) <= 8, "a finger that stopped for a tenth of a second reads as still, and old samples go")
assert(track([[5, 2]], 5, 2) == 0, "a single sample has no speed")

## ── The temperature scale ──
var halfway = mixColours([0, 10, 1], [10, 20, 1], 0.5)
assert(halfway[1] == 5 and halfway[2] == 15 and halfway[3] == 1 and len(halfway) == 3, "half of the way, channel by channel")
assert(mixColours([1, 2], [3, 4], 0)[2] == 2 and mixColours([1, 2], [3, 4], 1)[1] == 3, "the ends are the colours themselves")
func sameColour(a, b)
    return math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3]) < 1e-9
end
assert(sameColour(tempColour(-40), TEMP_STOPS[1][2]) and sameColour(tempColour(80), TEMP_STOPS[len(TEMP_STOPS)][2]), "held beyond the ends")
assert(sameColour(tempColour(10), TEMP_STOPS[3][2]), "exact on a step")
var mid = tempColour(14)
assert(mid[1] > TEMP_STOPS[3][2][1] and mid[1] < TEMP_STOPS[4][2][1], "between two steps it is between their colours")
assert(onTrack(5, 0, 10) == 0.5 and onTrack(-3, 0, 10) == 0 and onTrack(15, 0, 10) == 1, "held on the track")
assert(onTrack(7, 7, 7) == 0.5, "a track of no width has a middle")

## ── The skies and the bars ──
for code, sky in SKIES do
    assert(SKY[sky.kind] <> nil, "no sky for the kind {sky.kind} of the code {code}")
end
assert(SKY[skyOf(1234).kind] <> nil, "nor for a code the table does not know")
var bar = barColours(2, 12)
assert(len(bar) == 2 + BAR_SLICES and len(bar[1]) == 4, "the two ends and the slices between, as colours")
assert(sameColour(bar[1], tempColour(2)) and sameColour(bar[2], tempColour(12)) and sameColour(bar[3], tempColour(2.5)), "each in the colour of its temperature")
