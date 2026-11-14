## What every texts file must satisfy, whatever its words: a key missing from a language would show on the screen as
## nothing. Call checkLanguages() after importing the texts.

import "i18n.ol"

## The same keys, each of the same kind, at every depth.
func sameTexts(reference, table, where)
    for key, value in reference do
        assert(table[key] <> nil, "{where}: {key} is missing")
        assert(typeof(table[key]) == typeof(value), "{where}: {key} is not of the same kind")
        if typeof(value) == "map" then
            sameTexts(value, table[key], "{where}.{key}")
        end
    end
    for key in table do
        assert(reference[key] <> nil, "{where}: {key} is not in {i18n.languages[1]}")
    end
end

## The help of every language: a function of the figures of the rules, with as many paragraphs as the first language, none
## empty, no placeholder left, and every figure of `figures` (texts) in it.
func checkHelp(rules, figures)
    var reference = i18n.texts[i18n.languages[1]].help(rules)
    for code in i18n.languages do
        var paragraphs = i18n.texts[code].help(rules)
        assert(len(paragraphs) == len(reference), "{code}: the help has another number of paragraphs")
        for text in paragraphs do
            assert(len(text) > 0, "{code}: an empty paragraph")
            assert(text.find("\{") == nil, "{code}: a placeholder was not replaced in: {text}")
        end
        var all = paragraphs.join(" ")
        for figure in figures do
            assert(all.find(figure) <> nil, "{code}: the help lost {figure}")
        end
    end
end

func checkLanguages()
    var reference = i18n.texts[i18n.languages[1]]
    assert(i18n.lang == i18n.languages[1], "the first language is the one a program starts in")
    for code in i18n.languages do
        assert(i18n.texts[code] <> nil, "{code} is listed but has no texts")
        sameTexts(reference, i18n.texts[code], code)
        assert(setLanguage(code) and i18n.lang == code, "switching to {code}")
        assert(languageNamed(nameOfLanguage(code)) == code, "{code} is found again by its name")
    end
    assert(len(languageNames()) == len(i18n.languages))
    assert(setLanguage("xx") == false and languageNamed("xx") == nil, "an unknown language is refused")
    assert(i18n.lang == i18n.languages[len(i18n.languages)], "and changes nothing")
    setLanguage(i18n.languages[1])
end
