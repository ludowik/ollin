## The screens that replace the game (the options, the help, the catalogue of pieces, the languages) and the sound switch
## they hold.

func showScreen(name)
    assert(name == "game" or screens[name] <> nil, "unknown screen")
    game.screen = name
    game.screenTick = game.tick
end

## Switches the sound and keeps the choice for the next launch. A tap arrives twice in the same frame
## (touch, then the mouse the system emulates from it), and a switch is the one press that is not
## idempotent: the gesture is marked as handled, as a change of screen does.
func toggleSound()
    game.screenTick = game.tick
    if switchSound() then
        sounds.confirm.play()
    end
end

## The buttons of a menu screen, top to bottom: {label, primary, and what a press does: lead somewhere (goes), pick a language (lang) or switch the sound}.
func optionEntries()
    var entries = []
    for entry in config.menu do
        var key = entry.text
        var toggle = nil
        if entry.sound then
            key = soundSwitch.on and "menuSoundOn" or "menuSoundOff"
            toggle = toggleSound
        end
        entries.push({label: tr(key), goes: entry.goes, toggle: toggle, primary: entry.primary})
    end
    return entries
end

func backToOptions(x, y)
    showScreen("options")
end

## The screens that replace the game, by name: how each is drawn and what a press on it does.
global screens = {
    options: menuScreen("options", optionEntries),
    help: {draw: drawHelp, press: backToOptions},
    pieces: {draw: drawGallery, press: backToOptions},
    language: menuScreen("menuLanguage", languageEntries)
}
