## The screens before the game (docs/samples/tetris/screens.ol): what each says, where, and which choice is lit, for
## both styles that paint them.

import "screens.ol"

gameInit()

func texts(items)
    var out = []
    for it in items do
        if it.text then
            out.push(it.text)
        end
    end
    return out
end

func find(items, text)
    for it in items do
        if it.text == text then
            return it
        end
    end
    return nil
end

## Every item sits inside the frame of the screen (4 to 156 across, 4 to 140 down), a choice with its whole box.
func fits(items)
    for it in items do
        assert(it.x >= 4 and it.x <= 156 and it.y >= 4 and it.y <= 140, "{it.text} is out of the screen")
        if it.w then
            assert(it.x + it.w <= 156 and it.y + it.h <= 140 and it.w > 0 and it.h > 0, "{it.text} is out of the screen")
        end
    end
end

## The title: the name, the seven pieces each once, START while it shows, and the hint of the key V.
game.frame = 0
var title = titleItems("V  MODERN STYLE")
assert(title[1].text == "TETRIS" and title[1].size == 24 and title[1].logo == true)
for it in title do
    assert(it == title[1] or it.logo == nil, "only the name of the game is the logo")
end
var seen = {}
var pieces = 0
for it in title do
    if it.piece then
        pieces += 1
        seen[it.piece] = true
        assert(it.piece >= 1 and it.piece <= KINDS)
    end
end
assert(pieces == KINDS and len(seen) == KINDS)
assert(find(title, "PUSH START") <> nil)
assert(title[len(title)].text == "V  MODERN STYLE" and title[len(title)].dim == true and title[len(title)].size == 6)
fits(title)
game.frame = 39
assert(find(titleItems(""), "PUSH START") <> nil)
game.frame = 40
assert(find(titleItems(""), "PUSH START") == nil, "START blinks")
game.frame = 50
assert(find(titleItems(""), "PUSH START") == nil)
game.frame = 59
assert(find(titleItems(""), "PUSH START") == nil)
game.frame = 60
assert(find(titleItems(""), "PUSH START") <> nil)

## The menu: two types and two musics, and the one chosen is lit, blinking while the arrows are on its line.
game.frame = 0
game.type = "A"
music.on = true
game.focus = "type"
var menu = menuItems("")
assert(texts(menu).join(",") == "GAME TYPE,A-TYPE,B-TYPE,MUSIC,MUSIC-A,OFF,PUSH START")
assert(find(menu, "A-TYPE").lit == true and find(menu, "B-TYPE").lit == false)
assert(find(menu, "MUSIC-A").lit == true and find(menu, "OFF").lit == false)
fits(menu)
game.frame = 27
assert(find(menuItems(""), "A-TYPE").lit == true)
game.frame = 28
assert(find(menuItems(""), "A-TYPE").lit == false, "the chosen type blinks off at the 28th frame of 40")
game.frame = 30
menu = menuItems("")
assert(find(menu, "A-TYPE").lit == false, "the chosen type blinks while the arrows are on it")
assert(find(menu, "MUSIC-A").lit == true, "the music does not")
game.focus = "music"
game.type = "B"
music.on = false
menu = menuItems("")
assert(find(menu, "B-TYPE").lit == true and find(menu, "A-TYPE").lit == false)
assert(find(menu, "OFF").lit == false and find(menu, "MUSIC-A").lit == false, "the music blinks on its line")
game.frame = 0
assert(find(menuItems(""), "OFF").lit == true)

## The level screen: the levels, and for a B game the heights too.
game.type = "A"
game.focus = "level"
game.startLevel = 7
game.best = 12345
var level = levelItems()
assert(level[1].text == "A-TYPE" and find(level, "LEVEL") <> nil and find(level, "HEIGHT") == nil)
var choices = 0
for it in level do
    if it.w then
        choices += 1
    end
end
assert(choices == config.maxStartLevel + 1)
assert(find(level, "7").lit == true and find(level, "6").lit == false)
assert(find(level, "HIGH 012345").dim == true, "the best score is told in six digits")
fits(level)
game.type = "B"
game.focus = "height"
game.height = 3
level = levelItems()
assert(level[1].text == "B-TYPE" and find(level, "HEIGHT") <> nil)
choices = 0
for it in level do
    if it.w then
        choices += 1
    end
end
assert(choices == config.maxStartLevel + 1 + config.maxHeight + 1)
fits(level)
print("tetris screens ok")
