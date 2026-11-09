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
import "icons.ol"
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
const RETRY = 60                ## seconds before a page asks again after a failure
const STALE = 60                ## seconds after which a page that comes into view asks again
const NOTICE = 4                ## seconds a message of the search stays on the screen
const PLACE_KEY = "place"

global app = {
    pages: [],                  ## one per place: {place, weather, failure, view, age, request}; the cities, then at most one place that was searched
    index: 1,                   ## the page the screen settles on
    pos: 1,                     ## the page shown, fractional while the pages are dragged or slide
    dragging: false,
    grabX: 0,
    grabPos: 1,
    finger: 1,                  ## where the finger holds the pages, which pos follows with a spring while it is down
    dirty: false,               ## the page changed and is not saved yet
    trail: [],                  ## the samples [time, position] of the drag, which its speed is read from
    vel: 0,                     ## pages per second, while sliding
    layout: nil,                ## see layoutOf
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

## Gives up a request that may be out (nil when none is): its answer will never be delivered.
func giveUp(request)
    if request then
        request.cancel()
    end
end

func newPage(place)
    return {place: place, weather: nil, failure: nil, view: nil, age: 0, request: nil}
end

func onForecast(page, res)
    page.request = nil
    var weather = nil
    var why = nil
    if res.ok then
        weather, why = readForecast(res.body)
    end
    page.view = nil
    if weather then
        for day in weather.days do
            day.bar = barColours(day.low, day.high)
        end
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
    giveUp(page.request)
    if not page.weather then
        page.failure = nil
        page.view = nil
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

## The page of the place that was searched, after the cities, or nil.
func searchedPage()
    if len(app.pages) > len(CITIES) then
        return app.pages[len(app.pages)]
    end
    return nil
end

## What the next run starts from: the page, and the place that was searched if there is one.
func save()
    var searched = searchedPage()
    data.set(PLACE_KEY, {index: app.index, searched: searched and searched.place or nil})
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
    var page = newPage(place)
    var old = searchedPage()
    if old then
        giveUp(old.request)
        app.pages[len(app.pages)] = page
    else
        app.pages.push(page)
    end
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
    giveUp(app.search)
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

## The sky behind the weather of a page, or the waiting one while it has none.
func paletteOf(page)
    return page.weather and SKY[skyOf(page.weather.code).kind] or WAITING
end

## The sky at a position of the pages: the sky of the page, or the blend of the skies of the two pages it is between.
func skyAt(pos)
    var first, second, mix = skyBetween(pos, len(app.pages))
    var a = paletteOf(app.pages[first])
    if mix == 0 then
        return a
    end
    var b = paletteOf(app.pages[second])
    return [mixColours(a[1], b[1], mix), mixColours(a[2], b[2], mix)]
end

const WHITE = [1, 1, 1, 1]
const CARD = [0.05, 0.1, 0.2, 0.3]      ## the tint of a card, dark so that the white text keeps its contrast over a bright sky

## Where things stand and how big they are, which only changes with the size of the area and the language: made once, and
## again when either changes, since measuring texts and working out their places every frame was most of the cost of a
## frame in which two pages are drawn.
func layoutOf()
    var key = "{i18n.lang} {W}x{H}"
    if app.layout and app.layout.key == key then
        return app.layout
    end
    var column = math.min(W, H * 0.62)
    var width = column * 0.94
    var r = math.max(math.min(W, H) * 0.045, 16)      ## the magnifier that opens the search, left of the handle of the interface (the three bars the engine keeps in the corner)
    app.layout = {
        key: key,
        column: column,
        button: {x: W - H * 0.054 - r * 1.6, y: H * 0.07, r: r},
        card: {x: CX - width / 2, w: width, conditionsY: H * 0.47, conditionsH: H * 0.135, daysY: H * 0.625, daysH: H * 0.285},
        hintSize: fitSize(tr("hint"), column * 0.04, column * 0.95)
    }
    return app.layout
end

func onSearchButton(x, y)
    var b = layoutOf().button
    var reach = b.r * 1.4
    return (x - b.x) * (x - b.x) + (y - b.y) * (y - b.y) <= reach * reach
end

## What a page draws that only changes with its weather, the language or the area: the texts, and the sizes that make them
## fit. Made once and kept in page.view until one of them changes (page.view is cleared when an answer comes).
func viewOf(page, layout)
    var view = page.view
    if view and view.key == layout.key then
        return view
    end
    var column = layout.column
    view = {key: layout.key, name: placeLabel(page.place)}
    view.nameSize = fitSize(view.name, column * 0.08, math.min(column * 0.95, 2 * (layout.button.x - 1.4 * layout.button.r - CX)))
    var weather = page.weather
    if weather then
        var today = weather.days[1]
        var card = layout.card
        view.temp = "{weather.temp:.0f}°"
        view.tempSize = fitSize(view.temp, column * 0.34, column * 0.8)
        view.words = skyText(skyOf(weather.code))
        view.wordsSize = fitSize(view.words, column * 0.065, column * 0.9)
        view.highLow = tr("highLow")("{today.high:.0f}", "{today.low:.0f}")
        view.cells = []
        if weather.feels <> nil then
            view.cells.push({label: tr("feelsLike"), value: "{weather.feels:.0f}°"})
        end
        view.cells.push({label: tr("wind"), value: "{weather.wind:.0f} km/h"})
        for cell in view.cells do
            cell.size = fitSize(cell.value, card.conditionsH * 0.25, card.w / len(view.cells) * 0.9)
        end
        view.daysTitle = tr("forecastTitle")(math.min(len(weather.days), FORECAST_DAYS))
        view.days = []
        for i = 1, math.min(len(weather.days), FORECAST_DAYS) do
            var day = weather.days[i]
            view.days.push({
                label: i == 1 and tr("today") or date.weekdayName(day.weekday, i18n.lang, "short"),
                low: "{day.low:.0f}°", high: "{day.high:.0f}°"
            })
        end
    elseif page.failure then
        view.lines = wrapText(page.failure(), column * 0.055, column * 0.9)
    end
    page.view = view
    return view
end

## The magnifier that opens the search.
func drawSearchButton(b)
    fillC(WHITE, 0.18)
    graphics.circle(b.x, b.y, b.r)
    graphics.noFill()
    graphics.stroke(1, 1, 1, 0.95)
    graphics.strokeSize(b.r * 0.13)
    graphics.circle(b.x - b.r * 0.1, b.y - b.r * 0.1, b.r * 0.38)
    graphics.line(b.x + b.r * 0.18, b.y + b.r * 0.18, b.x + b.r * 0.5, b.y + b.r * 0.5)
    graphics.noStroke()
end

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
func drawConditions(view, card)
    var y = card.conditionsY
    var h = card.conditionsH
    drawCard(card.x, y, card.w, h, tr("conditions"))
    for i = 1, len(view.cells) do
        var cell = view.cells[i]
        var cx = card.x + card.w * (i - 0.5) / len(view.cells)
        drawText(cell.label, cx, y + h * 0.5, math.min(h * 0.14, card.w * 0.05), "center", "center", WHITE, 0.65)
        drawText(cell.value, cx, y + h * 0.77, cell.size, "center", "center", WHITE)
    end
end

## The bar of a day, from its low to its high on a track that shows the lowest and the highest of all the days: cold
## blue to warm orange along it (the colours of the day, made when the forecast arrived), and a white dot where the
## temperature now stands on the day it is for.
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
    fillC(day.bar[1])
    graphics.circle(from + h / 2, y, h / 2)
    fillC(day.bar[2])
    graphics.circle(to - h / 2, y, h / 2)
    for k = 0, BAR_SLICES - 1 do
        fillC(day.bar[3 + k])
        graphics.rect(from + h / 2 + inner * k / BAR_SLICES, y - h / 2, inner / BAR_SLICES + 1, h)
    end
    if now <> nil then
        fillC(WHITE)
        graphics.circle(x + w * onTrack(math.clamp(now, day.low, day.high), lo, hi), y, h * 0.8)
    end
end

## The card of the days to come, a row each: the day, its sky, its low, its range and its high.
func drawDays(weather, view, card)
    var x = card.x
    var y = card.daysY
    var w = card.w
    var h = card.daysH
    var n = len(view.days)
    drawCard(x, y, w, h, view.daysTitle)
    var lo = weather.days[1].low
    var hi = weather.days[1].high
    for i = 1, n do
        lo = math.min(lo, weather.days[i].low)
        hi = math.max(hi, weather.days[i].high)
    end
    var top = y + w * 0.12
    var rowH = (y + h - top - h * 0.03) / n
    var size = math.min(rowH * 0.46, w * 0.055)
    for i = 1, n do
        var day = weather.days[i]
        var text = view.days[i]
        var cy = top + (i - 0.5) * rowH
        if i > 1 then
            fillC(WHITE, 0.12)
            graphics.rect(x + w * 0.05, cy - rowH / 2, w * 0.9, 1)
        end
        drawText(text.label, x + w * 0.05, cy, size, "left", "center", WHITE)
        drawIcon(skyOf(day.code).kind, x + w * 0.31, cy, math.min(rowH * 0.3, w * 0.05))
        drawText(text.low, x + w * 0.5, cy, size, "right", "center", WHITE, 0.6)
        var now = nil
        if i == 1 then
            now = weather.temp          ## not `i == 1 and weather.temp or nil`: a temperature of 0 is falsy
        end
        drawRange(day, lo, hi, now, x + w * 0.54, cy, w * 0.26, math.max(rowH * 0.17, 4))
        drawText(text.high, x + w * 0.95, cy, size, "right", "center", WHITE)
    end
end

## One page, in the coordinates of the screen, over the sky: the place and the weather now, then two cards.
func drawPage(page, layout)
    var column = layout.column
    var view = viewOf(page, layout)
    drawText(view.name, CX, H * 0.07, view.nameSize, "center", "center", WHITE)
    if page.weather then
        drawText(view.temp, CX, H * 0.245, view.tempSize, "center", "center", WHITE)
        drawText(view.words, CX, H * 0.36, view.wordsSize, "center", "center", WHITE)
        drawText(view.highLow, CX, H * 0.41, column * 0.05, "center", "center", WHITE, 0.85)
        drawConditions(view, layout.card)
        drawDays(page.weather, view, layout.card)
    elseif view.lines then
        for i = 1, len(view.lines) do
            drawText(view.lines[i], CX, H * 0.4 + (i - 1) * column * 0.075, column * 0.055, "center", "center", WHITE)
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
    var layout = layoutOf()
    var sky = skyAt(app.pos)
    drawGradient(sky[1], sky[2])
    for i = 1, len(app.pages) do
        var offset = (i - app.pos) * W
        if offset > -W + 1 and offset < W - 1 then      ## a page less than a pixel wide on the screen is not drawn
            graphics.push()
            graphics.translate(offset, 0)
            drawPage(app.pages[i], layout)
            graphics.pop()
        end
    end
    drawDots(H * 0.93)
    if app.notice == "" then
        drawText(tr("hint"), CX, H * 0.972, layout.hintSize, "center", "center", WHITE, 0.7)
    else
        drawText(app.notice, CX, H * 0.972, fitSize(app.notice, layout.column * 0.04, layout.column * 0.95), "center", "center", WHITE)
    end
    drawSearchButton(layout.button)
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
