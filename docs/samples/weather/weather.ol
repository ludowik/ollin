## Weather: how it is now and over the next days in a city, asked of Open-Meteo, a free weather service, with the
## https and json modules. The cities are pages side by side, as in the weather application of a phone: drag the screen
## sideways (or press left and right) to pass from one to the next, and the dots at the bottom say which page it is.
## Every page keeps its own reading and asks the service again every ten minutes on its own, so a page that comes
## into view already shows its weather, and a page that is asked again keeps showing the old one until the answer
## replaces it. A name is looked up from the magnifier, or by typing: both open the text field of the engine's
## interface (ui.textField), which takes the keyboard of the system, the one of a phone included, so the accents, the
## hyphen and the apostrophe of a name come as the system makes them. Return or a touch elsewhere looks the name up,
## and the place found becomes one more page, after the cities. Return, when no field is open, asks again. The page
## and the language the last run left are kept from one run to the next. The app speaks French (the default) and
## English, chosen from the list of the interface: the words are in texts.ol, and a language is one more table there.
##
## An answer comes LATER: https.get returns at once and the function given to it runs when the service has answered,
## so a page with no weather yet says "loading". forecast.ol holds the addresses and the reading of the answers,
## pager.ol the motion of the pages, scale.ol the colours of a temperature, and weather_test.ol tries them, and the
## answers on texts written the way the service writes them. The service is reached from the browser, and only from it: elsewhere every request fails with
## "unsupported", which the screen reports.

import "forecast.ol"
import "pager.ol"
import "scale.ol"
import "texts.ol"
import "../lib/draw.ol"

const CITIES = [
    {id: "paris", lat: 48.8534, lon: 2.3488},
    {id: "london", lat: 51.5085, lon: -0.1257},
    {id: "newYork", lat: 40.7143, lon: -74.006},
    {id: "tokyo", lat: 35.6895, lon: 139.6917},
    {id: "sydney", lat: -33.8678, lon: 151.2073},
    {id: "reykjavik", lat: 64.1355, lon: -21.8954},
    {id: "cairo", lat: 30.0626, lon: 31.2497},
    {id: "rio", lat: -22.9028, lon: -43.2075}
]
const LANG_KEY = "lang"
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
const RETRY = 60                ## seconds before a page asks again after a failure
const STALE = 60                ## seconds after which a page that comes into view asks again
const NOTICE = 4                ## seconds a message of the search stays on the screen
const PLACE_KEY = "place"

global app = {
    pages: [],                  ## one per place: {place, weather, message, age, request}; the cities, then at most one place that was searched
    index: 1,                   ## the page the screen settles on
    pos: 1,                     ## the page shown, fractional while the pages are dragged or slide
    dragging: false,
    grabX: 0,
    grabPos: 1,
    finger: 1,                  ## where the finger holds the pages, which pos follows with a spring while it is down
    dirty: false,               ## the page changed and is not saved yet
    trail: [],                  ## the samples [time, position] of the drag, which its speed is read from
    vel: 0,                     ## pages per second, while sliding
    typing: "",                 ## the name being typed, which the text field of the interface edits
    search: nil,                ## the request for a name, while it is out
    notice: "",                 ## what a search has to say, for a few seconds
    noticeAge: 0
}

## ── Asking ─────────────────────────────────────────────────────────────────────────────────────────

## What a failed request means to the person looking at the screen, in the language of the moment.
func describe(res)
    if res.error == "unsupported" then
        return tr("noNetwork")
    elseif res.error == "timeout" then
        return tr("timeout")
    elseif res.error then
        return tr("noAnswer")
    end
    return reasonOf(res.body) or tr("answered")(res.status)
end

## The name of a place and of its country: the table of the language for a city of the list, what the search service wrote
## for a place that was searched.
func placeLabel(place)
    var names = [place.name, place.country]
    if place.id then
        names = tr("cities")[place.id]
    end
    if names[2] == "" then
        return names[1]
    end
    return "{names[1]}, {names[2]}"
end

func newPage(place)
    return {place: place, weather: nil, failure: nil, age: 0, request: nil}
end

func onForecast(page, res)
    page.request = nil
    var weather = nil
    var why = nil
    if res.ok then
        weather, why = readForecast(res.body)
    end
    if weather then
        page.weather = weather
        page.failure = nil
        page.age = 0
        return
    end
    page.age = REFRESH - RETRY
    if not page.weather then
        ## a page that has a weather keeps it: an old reading is better than a message. The message is made when it is
        ## shown, so that it follows a change of language.
        page.failure = func()
            return why and tr("cannotRead")(reasonText(why)) or describe(res)
        end
    end
end

## Asks the weather of a page. The previous request, if one is still out, is given up. The weather the page already has
## stays on it until the answer replaces it, so that asking again does not flash.
func ask(page)
    if page.request then
        page.request.cancel()
    end
    if not page.weather then
        page.failure = nil
    end
    page.age = 0
    page.request = https.get(forecastUrl(page.place.lat, page.place.lon), {timeout: TIMEOUT}, func(res)
        onForecast(page, res)
    end)
end

func say(text)
    app.notice = text
    app.noticeAge = 0
end

## What the next run starts from: the page, and the place that was searched if there is one.
func save()
    var searched = nil
    if len(app.pages) > len(CITIES) then
        searched = app.pages[len(app.pages)].place
    end
    data.set(PLACE_KEY, {index: app.index, searched: searched})
end

## Settles on a page, asking it again if what it shows is old.
func settle(index)
    app.index = math.clamp(index, 1, len(app.pages))
    app.vel = launch(app.pos, app.vel, app.index)
    var page = app.pages[app.index]
    if page.age >= STALE and not page.request then
        ask(page)
    end
    app.dirty = true
end

func nearPlace(a, b)
    return math.abs(a.lat - b.lat) < 0.05 and math.abs(a.lon - b.lon) < 0.05
end

## Brings the place found by a search to the screen: the page that already shows it, or a page of its own, which takes
## the place of the page of the last search.
func show(place)
    for i = 1, len(app.pages) do
        if nearPlace(app.pages[i].place, place) then
            settle(i)
            return
        end
    end
    if len(app.pages) > len(CITIES) then
        var old = app.pages.pop()
        if old.request then
            old.request.cancel()
        end
        app.index = math.min(app.index, len(app.pages))
        app.pos = math.min(app.pos, len(app.pages))
    end
    var page = newPage(place)
    app.pages.push(page)
    ask(page)
    settle(len(app.pages))
end

func onPlace(name, res)
    app.search = nil
    if not res.ok then
        say(describe(res))
        return
    end
    var place, why = readPlace(res.body)
    if not place then
        say(why == "noPlace" and tr("noPlace")(name) or tr("cannotRead")(reasonText(why)))
        return
    end
    app.notice = ""
    show(place)
end

func search(name)
    if app.search then
        app.search.cancel()
    end
    say(tr("lookingFor")(name))
    app.search = https.get(searchUrl(name, i18n.lang), {timeout: TIMEOUT}, func(res)
        onPlace(name, res)
    end)
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

global searchField = nil
global languageName = nil

## A language chosen from the list of the interface: kept for the next run, and the interface is declared again in it.
func chooseLanguage(name)
    for code in LANGUAGES do
        if TEXTS[code].name == name and setLanguage(code) then
            data.set(LANG_KEY, code)
            buildInterface()
        end
    end
end

## The widgets of the interface, in the language of the moment: the field a name is typed in, and the list of languages.
## Declared again at every change of language, the label of a widget being fixed when it is declared.
func buildInterface()
    ui.clear()
    languageName = tr("name")
    searchField = ui.textField(tr("cityLabel"), ref app.typing, 30, tr("cityPlaceholder"), lookUp)
    var names = []
    for code in LANGUAGES do
        names.push(TEXTS[code].name)
    end
    ui.list(tr("languageLabel"), names, ref languageName, chooseLanguage)
end

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
        ask(app.pages[app.index])
    elseif key == "left" then
        settle(app.index - 1)
    elseif key == "right" then
        settle(app.index + 1)
    end
end

## A touch on the screen takes the pages, which then follow the finger (update reads where it is) until it lets go.
func mouse.pressed(x, y)
    if onSearchButton(x, y) then
        openSearch()
        return
    end
    app.dragging = true
    app.grabX = x
    app.grabPos = app.pos
    app.vel = 0
    app.finger = app.pos
    app.trail = [[elapsedTime, app.pos]]
end

## The pages follow the finger, now at x: where they are, and the speed of the drag.
func follow(x)
    app.finger = dragPos(app.grabPos, app.grabX, x, W, len(app.pages))
    return track(app.trail, elapsedTime, app.finger)
end

## Lets go of the pages, the finger being at x: they settle on the page the drag points to, going on at its speed.
func release(x)
    var speed = follow(x)
    app.dragging = false
    app.vel = speed
    settle(pageAfterDrag(app.finger, speed, app.index, len(app.pages)))
end

func mouse.released(x, y)
    if app.dragging then
        release(x)
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

## The sky behind the weather of a page, or the waiting one while it has none.
func paletteOf(page)
    return page.weather and SKY[skyOf(page.weather.code).kind] or WAITING
end

func drawSky(palette)
    drawGradient(palette[1], palette[2])
end

## The sky at a position of the pages: the sky of the page, or the blend of the skies of the two pages it is between.
func skyAt(pos)
    var first, second, mix = skyBetween(pos, len(app.pages))
    var a = paletteOf(app.pages[first])
    var b = paletteOf(app.pages[second])
    var out = []
    for i = 1, 2 do
        var colour = []
        for k = 1, 3 do
            colour.push(a[i][k] + (b[i][k] - a[i][k]) * mix)
        end
        out.push(colour)
    end
    return out
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

const CARD = [0.05, 0.1, 0.2, 0.3]      ## the tint of a card, dark so that the white text keeps its contrast over a bright sky

## A card over the sky: a rounded, tinted panel with a faint edge, and its title.
func drawCard(x, y, w, h, title)
    var r = w * 0.045
    fillC(WHITE, 0.1)
    graphics.rect(x - 1, y - 1, w + 2, h + 2, r + 1)
    fillC(CARD)
    graphics.rect(x, y, w, h, r)
    drawText(title, x + w * 0.05, y + w * 0.065, w * 0.042, "left", "center", WHITE, 0.65)
end

## The card of what the weather feels like now: a few figures side by side, each with its label.
func drawConditions(weather, x, y, w, h)
    drawCard(x, y, w, h, tr("conditions"))
    var cells = []
    if weather.feels <> nil then
        cells.push([tr("feelsLike"), "{weather.feels:.0f}°"])
    end
    cells.push([tr("wind"), "{weather.wind:.0f} km/h"])
    for i = 1, len(cells) do
        var cx = x + w * (i - 0.5) / len(cells)
        drawText(cells[i][1], cx, y + h * 0.5, math.min(h * 0.14, w * 0.05), "center", "center", WHITE, 0.65)
        drawText(cells[i][2], cx, y + h * 0.77, fitSize(cells[i][2], h * 0.25, w / len(cells) * 0.9), "center", "center", WHITE)
    end
end

## The bar of a day, from its low to its high on a track that shows the lowest and the highest of all the days: cold
## blue to warm orange along it, and a white dot where the temperature now stands on the day it is for.
func drawRange(day, lo, hi, now, x, y, w, h)
    fillC(WHITE, 0.15)
    graphics.rect(x, y - h / 2, w, h, h / 2)
    var from = x + w * onTrack(day.low, lo, hi)
    var to = math.max(x + w * onTrack(day.high, lo, hi), from + h)
    if to > x + w then
        to = x + w
        from = to - h
    end
    var inner = to - from - h
    fillC(tempColour(day.low))
    graphics.circle(from + h / 2, y, h / 2)
    fillC(tempColour(day.high))
    graphics.circle(to - h / 2, y, h / 2)
    var slices = 10
    for k = 0, slices - 1 do
        fillC(tempColour(day.low + (day.high - day.low) * (k + 0.5) / slices))
        graphics.rect(from + h / 2 + inner * k / slices, y - h / 2, inner / slices + 1, h)
    end
    if now <> nil then
        fillC(WHITE)
        graphics.circle(x + w * onTrack(math.clamp(now, day.low, day.high), lo, hi), y, h * 0.8)
    end
end

## The card of the days to come, a row each: the day, its sky, its low, its range and its high.
func drawDays(weather, x, y, w, h)
    var days = weather.days
    var n = math.min(len(days), FORECAST_DAYS)
    drawCard(x, y, w, h, tr("forecastTitle")(n))
    var lo = days[1].low
    var hi = days[1].high
    for i = 1, n do
        lo = math.min(lo, days[i].low)
        hi = math.max(hi, days[i].high)
    end
    var top = y + w * 0.12
    var rowH = (y + h - top - h * 0.03) / n
    var size = math.min(rowH * 0.46, w * 0.055)
    for i = 1, n do
        var day = days[i]
        var cy = top + (i - 0.5) * rowH
        if i > 1 then
            fillC(WHITE, 0.12)
            graphics.rect(x + w * 0.05, cy - rowH / 2, w * 0.9, 1)
        end
        drawText(i == 1 and tr("today") or date.weekdayName(day.weekday, i18n.lang, "short"), x + w * 0.05, cy, size, "left", "center", WHITE)
        drawIcon(skyOf(day.code).kind, x + w * 0.31, cy, math.min(rowH * 0.3, w * 0.05))
        drawText("{day.low:.0f}°", x + w * 0.5, cy, size, "right", "center", WHITE, 0.6)
        drawRange(day, lo, hi, i == 1 and weather.temp or nil, x + w * 0.54, cy, w * 0.26, math.max(rowH * 0.17, 4))
        drawText("{day.high:.0f}°", x + w * 0.95, cy, size, "right", "center", WHITE)
    end
end

## One page, in the coordinates of the screen, over the sky: the place and the weather now, then two cards.
func drawPage(page)
    var column = math.min(W, H * 0.62)
    var weather = page.weather
    var name = placeLabel(page.place)
    var button = searchButton()
    var room = math.min(column * 0.95, 2 * (button.x - 1.4 * button.r - CX))       ## the magnifier and the handle take the right, and the title is centred
    drawText(name, CX, H * 0.07, fitSize(name, column * 0.08, room), "center", "center", WHITE)
    if weather then
        var sky = skyOf(weather.code)
        var temp = "{weather.temp:.0f}°"
        var today = weather.days[1]
        drawText(temp, CX, H * 0.245, fitSize(temp, column * 0.34, column * 0.8), "center", "center", WHITE)
        var words = skyText(sky)
        drawText(words, CX, H * 0.36, fitSize(words, column * 0.065, column * 0.9), "center", "center", WHITE)
        drawText(tr("highLow")("{today.high:.0f}", "{today.low:.0f}"), CX, H * 0.41, column * 0.05, "center", "center", WHITE, 0.85)
        var card = column * 0.94
        drawConditions(weather, CX - card / 2, H * 0.47, card, H * 0.135)
        drawDays(weather, CX - card / 2, H * 0.625, card, H * 0.285)
    elseif page.failure then
        var lines = wrap(page.failure(), 26)
        for i = 1, len(lines) do
            drawText(lines[i], CX, H * 0.4 + (i - 1) * column * 0.075, column * 0.055, "center", "center", WHITE)
        end
    else
        drawText(tr("loading"), CX, H * 0.4, column * 0.08, "center", "center", WHITE, 0.8)
    end
end

## One dot per page, the nearer the pages are to the screen the brighter its dot.
func drawDots(y)
    var r = math.max(math.min(W, H) * 0.011, 3)
    var n = len(app.pages)
    var spacing = r * 3.4
    for i = 1, n do
        fillC(WHITE, 1 - 0.6 * math.min(1, math.abs(i - app.pos)))
        graphics.circle(CX + (i - (n + 1) / 2) * spacing, y, r)
    end
end

func draw()
    graphics.font("sans")
    graphics.noStroke()
    drawSky(skyAt(app.pos))
    for i = 1, len(app.pages) do
        var offset = (i - app.pos) * W
        if offset > -W and offset < W then
            graphics.push()
            graphics.translate(offset, 0)
            drawPage(app.pages[i])
            graphics.pop()
        end
    end
    var column = math.min(W, H * 0.62)
    drawDots(H * 0.93)
    var text = app.notice
    if text == "" then
        text = tr("hint")
    end
    drawText(text, CX, H * 0.972, fitSize(text, column * 0.04, column * 0.95), "center", "center", WHITE, app.notice == "" and 0.7 or 1)
    drawSearchButton()
end

func update(dt)
    for page in app.pages do
        page.age += dt
        if page.age >= REFRESH and not page.request then
            ask(page)
        end
    end
    if app.dragging then
        if mouse.isDown() then
            follow(mouse.position())
            app.pos, app.vel = slide(app.pos, app.vel, app.finger, dt, FOLLOW)
        else
            release(mouse.position())       ## a release that was never reported (the system takes the touch away) must not leave the pages held
        end
    else
        app.pos, app.vel = slide(app.pos, app.vel, app.index, dt)
        if app.dirty and app.pos == app.index then
            save()              ## once the pages have come to rest: writing the store in the middle of a slide would cost a frame
            app.dirty = false
        end
    end
    app.noticeAge += dt
    if app.noticeAge >= NOTICE and not app.search then
        app.notice = ""
    end
end

## A place read from the store, or nil. A store is read and not trusted: it gets the checks an answer of the service
## gets, so that a damaged one gives the first city instead of a request that cannot be made.
func cleanPlace(place)
    if typeof(place) <> "map" or typeof(place.name) <> "string" or not numbersOf([place.lat, place.lon], 2) then
        return nil
    end
    return {name: place.name, country: typeof(place.country) == "string" and place.country or "", lat: place.lat, lon: place.lon}
end

func setup()
    setLanguage(data.get(LANG_KEY, i18n.lang))
    graphics.canvas(W, H, tr("windowTitle"))
    graphics.fitArea()
    buildInterface()
    for city in CITIES do
        app.pages.push(newPage(city))
    end
    var saved = data.get(PLACE_KEY)
    var index = 1
    if typeof(saved) == "map" then
        var searched = cleanPlace(saved.searched)
        if searched then
            app.pages.push(newPage(searched))
        end
        index = typeof(saved.index) == "int" and saved.index or 1
    end
    app.index = math.clamp(index, 1, len(app.pages))
    app.pos = app.index
    for page in app.pages do
        ask(page)
    end
end
