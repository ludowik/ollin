## Weather: how it is now and over the next days in a city, asked of Open-Meteo, a free weather service, with the
## https and json modules. Left and right (the keys, or a tap on either side of the screen) change the city; a tap in
## the middle asks again. A name is looked up from the magnifier, or by typing: both open the text field of the engine's
## interface (ui.textField), which takes the keyboard of the system, the one of a phone included, so the accents, the
## hyphen and the apostrophe of a name come as the system makes them. Return or a touch elsewhere looks the name up. The
## weather is asked again every ten minutes on its own. The place is kept from one run to the next.
##
## An answer comes LATER: https.get returns at once and the function given to it runs when the service has answered,
## so the screen says "loading" until then. forecast.ol holds the addresses and the reading of the answers, and
## weather_test.ol tries them on texts written the way the service writes them. The service is reached from the
## browser, and only from it: elsewhere every request fails with "unsupported", which the screen reports.

import "forecast.ol"
import "../lib/draw.ol"

const CITIES = [
    {name: "Paris", country: "France", lat: 48.8534, lon: 2.3488},
    {name: "London", country: "United Kingdom", lat: 51.5085, lon: -0.1257},
    {name: "New York", country: "United States", lat: 40.7143, lon: -74.006},
    {name: "Tokyo", country: "Japan", lat: 35.6895, lon: 139.6917},
    {name: "Sydney", country: "Australia", lat: -33.8678, lon: 151.2073},
    {name: "Reykjavik", country: "Iceland", lat: 64.1355, lon: -21.8954},
    {name: "Cairo", country: "Egypt", lat: 30.0626, lon: 31.2497},
    {name: "Rio de Janeiro", country: "Brazil", lat: -22.9028, lon: -43.2075}
]
const REFRESH = 600             ## seconds before the weather is asked again
const TIMEOUT = 15              ## seconds the service has to answer
const SKY = {                   ## the top and the bottom of the sky behind each kind of weather
    clear: [[0.16, 0.45, 0.85], [0.52, 0.76, 0.96]],
    partly: [[0.25, 0.5, 0.82], [0.62, 0.78, 0.92]],
    cloud: [[0.38, 0.45, 0.55], [0.66, 0.71, 0.77]],
    fog: [[0.5, 0.55, 0.6], [0.74, 0.77, 0.8]],
    rain: [[0.17, 0.25, 0.4], [0.4, 0.5, 0.62]],
    snow: [[0.45, 0.55, 0.68], [0.82, 0.87, 0.93]],
    storm: [[0.1, 0.1, 0.22], [0.32, 0.3, 0.45]]
}
const WAITING = [[0.12, 0.2, 0.38], [0.3, 0.42, 0.6]]
const PLACE_KEY = "place"

global app = {
    place: CITIES[1],
    index: 1,                   ## the city of the list the place comes from, or 0 for a place that was searched
    weather: nil,               ## the reading of the last answer, nil until there is one
    status: "loading",          ## loading, ready or failed
    message: "",                ## what went wrong, when it failed
    age: 0,                     ## seconds since the weather was asked
    typing: "",                 ## the name being typed, which the text field of the interface edits
    request: nil
}

## ── Asking ─────────────────────────────────────────────────────────────────────────────────────────

## What a failed request means to the person looking at the screen.
func describe(res)
    if res.error == "unsupported" then
        return "This build has no network: the weather is asked from the browser."
    elseif res.error == "timeout" then
        return "The service did not answer in time."
    elseif res.error then
        return "No answer: the network is down, or the service does not allow this page to ask."
    end
    return reasonOf(res.body) or "The service answered {res.status}."
end

func fail(message)
    app.status = "failed"
    app.message = message
    app.request = nil
end

func stopAsking()
    if app.request then
        app.request.cancel()
        app.request = nil
    end
end

func onForecast(res)
    app.request = nil
    if not res.ok then
        fail(describe(res))
        return
    end
    var weather, why = readForecast(res.body)
    if not weather then
        fail("Cannot read the answer: {why}.")
        return
    end
    app.weather = weather
    app.status = "ready"
    app.age = 0
end

## Asks the weather of the place. The previous request, if one is still out, is given up: its answer would be for
## another place.
func ask()
    stopAsking()
    app.status = "loading"
    app.request = https.get(forecastUrl(app.place.lat, app.place.lon), {timeout: TIMEOUT}, onForecast)
end

func goTo(place, index)
    app.place = place
    app.index = index
    data.set(PLACE_KEY, {place: place, index: index})
    app.weather = nil
    app.age = 0
    ask()
end

func onPlace(name, res)
    app.request = nil
    if not res.ok then
        fail(describe(res))
        return
    end
    var place, why = readPlace(res.body)
    if not place then
        fail(why == "no such place" and "No place is called {name}." or "{why}.")
        return
    end
    goTo(place, 0)
end

func search(name)
    stopAsking()
    app.weather = nil
    app.status = "loading"
    app.request = https.get(searchUrl(name), {timeout: TIMEOUT}, func(res)
        onPlace(name, res)
    end)
end

func step(by)
    var n = len(CITIES)
    var i = ((app.index - 1 + by) % n + n) % n + 1    ## % keeps the sign of its left side, so a step back from the first city needs the second %
    goTo(CITIES[i], i)
end

## The name is edited by the engine's text field, which owns the keyboard while it is open and calls this when the name is
## validated. An empty name only closes the interface.
func lookUp(name)
    app.typing = ""
    ui.close()
    name = string.trim(name)
    if name <> "" then
        search(name)
    end
end

global searchField = ui.textField("City", ref app.typing, 30, "Type a city name", lookUp)

func openSearch()
    app.typing = ""
    searchField.edit()
end

## The search button, in the title row, left of the handle of the interface (the three bars the engine keeps in the corner).
func searchButton()
    var r = math.max(math.min(W, H) * 0.045, 16)
    return {x: W - H * 0.054 - r * 1.6, y: H * 0.07, r: r}
end

func onSearchButton(x, y)
    var b = searchButton()
    var reach = b.r * 1.4
    return (x - b.x) * (x - b.x) + (y - b.y) * (y - b.y) <= reach * reach
end

## ── Input ──────────────────────────────────────────────────────────────────────────────────────────

## A text typed while the field is closed opens it with that text, as typing a letter always did, unless it is only spaces.
## Once it is open the field takes the keys itself: neither typed nor keypressed is called.
func keyboard.typed(chars)
    if string.trim(chars) == "" then
        return
    end
    app.typing = string.substr(chars, 1, 30)
    searchField.edit()
end

## The keys that WRITE nothing, by name.
func keyboard.keypressed(key)
    if key == "return" then
        goTo(app.place, app.index)
    elseif key == "left" then
        step(-1)
    elseif key == "right" then
        step(1)
    end
end

func mouse.pressed(x, y)
    if onSearchButton(x, y) then
        openSearch()
    elseif x < W * 0.3 then
        step(-1)
    elseif x > W * 0.7 then
        step(1)
    else
        goTo(app.place, app.index)
    end
end

## ── Drawing ────────────────────────────────────────────────────────────────────────────────────────

## A text cut into lines of at most `width` characters, between words.
func wrap(text, width)
    var lines = []
    var line = ""
    for word in text.split(" ") do
        if line <> "" and len(line) + 1 + len(word) > width then
            lines.push(line)
            line = word
        elseif line == "" then
            line = word
        else
            line = "{line} {word}"
        end
    end
    lines.push(line)
    return lines
end

func drawSky(palette)
    drawGradient(palette[1], palette[2], 32)
end

func drawCloud(x, y, r, shade)
    fillC([shade, shade, shade, 1])
    graphics.circle(x - r * 0.55, y + r * 0.1, r * 0.5)
    graphics.circle(x + r * 0.1, y - r * 0.2, r * 0.65)
    graphics.circle(x + r * 0.65, y + r * 0.15, r * 0.45)
    graphics.rect(x - r * 0.55, y + r * 0.1, r * 1.2, r * 0.5)
end

func drawSun(x, y, r)
    graphics.stroke(1, 0.85, 0.3, 1)
    graphics.strokeSize(math.max(r * 0.12, 1))
    for i = 0, 7 do
        var a = (i / 8 + elapsedTime * 0.03) * math.TAU
        graphics.line(x + math.cos(a) * r * 1.25, y + math.sin(a) * r * 1.25, x + math.cos(a) * r * 1.65, y + math.sin(a) * r * 1.65)
    end
    graphics.noStroke()
    fillC([1, 0.85, 0.3, 1])
    graphics.circle(x, y, r)
end

## The picture of a kind of weather, `r` being about the size of its cloud or sun.
func drawIcon(kind, x, y, r)
    if kind == "clear" then
        drawSun(x, y, r * 0.8)
    elseif kind == "partly" then
        drawSun(x - r * 0.45, y - r * 0.4, r * 0.55)
        drawCloud(x + r * 0.1, y + r * 0.2, r, 1)
    else
        drawCloud(x, y - r * 0.15, r, kind == "storm" and 0.55 or kind == "rain" and 0.8 or 0.97)
        graphics.stroke(0.55, 0.75, 1, 1)
        graphics.strokeSize(math.max(r * 0.07, 1))
        if kind == "rain" then
            for i = -1, 1 do
                var drift = (elapsedTime * 1.5 + i * 0.37) % 1
                graphics.line(x + i * r * 0.5 + drift * r * 0.1, y + r * 0.55 + drift * r * 0.3,
                              x + i * r * 0.5 - r * 0.08 + drift * r * 0.1, y + r * 0.8 + drift * r * 0.3)
            end
        elseif kind == "snow" then
            graphics.noStroke()
            fillC([1, 1, 1, 1])
            for i = -1, 1 do
                var drift = (elapsedTime * 0.6 + i * 0.31) % 1
                graphics.circle(x + i * r * 0.5 + math.sin(elapsedTime * 2 + i) * r * 0.08, y + r * 0.5 + drift * r * 0.4, r * 0.07)
            end
        elseif kind == "fog" then
            graphics.stroke(1, 1, 1, 0.8)
            for i = 0, 2 do
                graphics.line(x - r * 0.8 + i * r * 0.15, y + r * 0.55 + i * r * 0.2, x + r * 0.8 - i * r * 0.15, y + r * 0.55 + i * r * 0.2)
            end
        elseif kind == "storm" then
            graphics.stroke(1, 0.9, 0.3, 1)
            graphics.line(x + r * 0.1, y + r * 0.4, x - r * 0.15, y + r * 0.7)
            graphics.line(x - r * 0.15, y + r * 0.7, x + r * 0.1, y + r * 0.7)
            graphics.line(x + r * 0.1, y + r * 0.7, x - r * 0.1, y + r * 1.0)
        end
        graphics.noStroke()
    end
end

const WHITE = [1, 1, 1, 1]

## The magnifier that opens the search.
func drawSearchButton()
    var b = searchButton()
    fillC(WHITE, 0.18)
    graphics.circle(b.x, b.y, b.r)
    graphics.noFill()
    graphics.stroke(1, 1, 1, 0.95)
    graphics.strokeSize(b.r * 0.13)
    graphics.circle(b.x - b.r * 0.1, b.y - b.r * 0.1, b.r * 0.38)
    graphics.line(b.x + b.r * 0.18, b.y + b.r * 0.18, b.x + b.r * 0.5, b.y + b.r * 0.5)
    graphics.noStroke()
end

func drawForecast(x, y, w, h)
    var days = app.weather.days
    var n = math.min(len(days), FORECAST_DAYS)
    var cell = w / n
    for i = 1, n do
        var day = days[i]
        var cx = x + (i - 0.5) * cell
        var label = i == 1 and "Today" or day.dayName
        drawText(label, cx, y + h * 0.1, fitSize(label, h * 0.17, cell * 0.9), "center", "center", WHITE)
        drawIcon(skyOf(day.code).kind, cx, y + h * 0.48, math.min(cell * 0.28, h * 0.2))
        drawText("{day.high:.0f}°", cx, y + h * 0.78, h * 0.17, "center", "center", WHITE)
        drawText("{day.low:.0f}°", cx, y + h * 0.95, h * 0.14, "center", "center", WHITE, 0.65)
    end
end

func draw()
    graphics.font("sans")
    graphics.noStroke()
    var column = math.min(W, H * 0.62)
    var ready = app.status == "ready" and app.weather
    var sky = ready and skyOf(app.weather.code) or nil
    drawSky(sky and SKY[sky.kind] or WAITING)
    var name = app.place.name
    if app.place.country <> "" then
        name = "{name}, {app.place.country}"
    end
    var button = searchButton()
    var room = math.min(column * 0.95, 2 * (button.x - 1.4 * button.r - CX))       ## the magnifier and the handle take the right, and the title is centred
    drawText(name, CX, H * 0.07, fitSize(name, column * 0.08, room), "center", "center", WHITE)
    if ready then
        drawIcon(sky.kind, CX, H * 0.22, column * 0.14)
        drawText("{app.weather.temp:.0f}°", CX, H * 0.4, column * 0.3, "center", "center", WHITE)
        drawText(sky.text, CX, H * 0.52, fitSize(sky.text, column * 0.065, column * 0.95), "center", "center", WHITE)
        drawText("Wind {app.weather.wind:.0f} km/h", CX, H * 0.585, column * 0.045, "center", "center", WHITE, 0.8)
        drawForecast(CX - column * 0.5, H * 0.65, column, H * 0.25)
    elseif app.status == "failed" then
        var lines = wrap(app.message, 26)
        for i = 1, len(lines) do
            drawText(lines[i], CX, H * 0.4 + (i - 1) * column * 0.075, column * 0.055, "center", "center", WHITE)
        end
    else
        drawText("Loading…", CX, H * 0.4, column * 0.08, "center", "center", WHITE, 0.8)
    end
    var hint = "< >  another city      type a name, or touch the magnifier"
    drawText(hint, CX, H * 0.95, fitSize(hint, column * 0.04, column * 0.95), "center", "center", WHITE, 0.7)
    drawSearchButton()
end

func update(dt)
    app.age += dt
    if app.age >= REFRESH and app.status <> "loading" then
        app.age = 0
        ask()
    end
end

## The place the last run left, or nil. A store is read and not trusted: it gets the checks an answer of the
## service gets, so that a damaged one gives the first city instead of a request that cannot be made.
func savedPlace()
    var saved = data.get(PLACE_KEY)
    if typeof(saved) <> "map" or typeof(saved.place) <> "map" or typeof(saved.index) <> "int" then
        return nil
    end
    if typeof(saved.place.name) <> "string" or not numbersOf([saved.place.lat, saved.place.lon], 2) then
        return nil
    end
    return saved.place, saved.index
end

func setup()
    graphics.canvas(W, H, "Weather")
    graphics.fitArea()
    var place, index = savedPlace()
    if place then
        app.place = place
        app.index = index
    end
    ask()
end
