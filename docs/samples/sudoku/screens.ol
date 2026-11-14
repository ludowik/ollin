## The screens that replace the game (the options, the languages, the choice of a level, the help) and the settings they switch.

func showScreen(name)
    game.screen = name
end

## A tap arrives twice in the same frame (touch, then the mouse the system emulates from it), and a switch is the
## one press that is not idempotent: press() ignores the second path of the same gesture.
func toggleSound()
    if switchSound() then
        sounds.confirm.play()
    end
end

func toggleErrors()
    game.errors = not game.errors
    data.set(config.errorsKey, game.errors)
end

func toggleInput()
    if game.input == "cell" then
        game.input = "digit"
    else
        game.input = "cell"
    end
    game.armed = 0
    data.set(config.inputKey, game.input)
end

func optionEntries()
    var soundKey = "menuSoundOff"
    if soundSwitch.on then
        soundKey = "menuSoundOn"
    end
    var errorsKey = "menuErrorsOff"
    if game.errors then
        errorsKey = "menuErrorsOn"
    end
    var inputKey = "menuInputCell"
    if game.input == "digit" then
        inputKey = "menuInputDigit"
    end
    return [
        {label: tr("menuHelp"), goes: "help"},
        {label: tr("menuLanguage"), goes: "language"},
        {label: tr(soundKey), toggle: toggleSound},
        {label: tr(errorsKey), toggle: toggleErrors},
        {label: tr(inputKey), toggle: toggleInput},
        {label: tr("menuBack"), goes: "play", primary: true}
    ]
end

func helpParagraphs()
    return tr("help")({box: BOX, size: N, hints: HINTS})
end

func startFromEntry(entry)
    startGame(entry.level, entry.daily)
end

func newEntries()
    var entries = []
    for level = 1, 4 do
        entries.push({label: levelName(level), level: level})
    end
    entries.push({label: tr("daily"), goes: "daily", primary: true})
    entries.push({label: tr("back"), goes: "play"})
    return entries
end

func dailyEntries()
    var entries = []
    var now = today()
    for level = 1, 4 do
        entries.push({label: levelName(level), level: level, daily: now, done: game.done[dailyKey(now, level)] == true})
    end
    entries.push({label: tr("back"), goes: "new"})
    return entries
end

## The screens that replace the game, by name: how each is drawn and what a press on it does.
global screens = {
    options: menuScreen("options", optionEntries),
    language: menuScreen("menuLanguage", languageEntries),
    new: menuScreen("chooseLevel", newEntries, startFromEntry),
    daily: menuScreen("daily", dailyEntries, startFromEntry),
    help: helpScreen(helpParagraphs),
    generating: {draw: drawGenerating, press: func(x, y) end}
}
