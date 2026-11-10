## The language a program speaks and the words it says in it. A program declares its languages once, in its texts
## file (useLanguages), and says everything through tr(key).

global i18n = {lang: nil, languages: [], texts: {}, key: nil}

## `languages` in the order of the language menu, the first being the default; `texts` the table of each, by code, every
## one with a `name` (the language in its own tongue); `key` is where the choice is kept between two runs.
func useLanguages(languages, texts, key)
    i18n.languages = languages
    i18n.texts = texts
    i18n.key = key
    i18n.lang = languages[1]
end

func tr(key)
    return i18n.texts[i18n.lang][key]
end

## Switches language; an unknown code changes nothing. Says whether it did.
func setLanguage(code)
    if i18n.texts[code] == nil then
        return false
    end
    i18n.lang = code
    return true
end

func nameOfLanguage(code)
    return i18n.texts[code].name
end

func languageNames()
    var names = []
    for code in i18n.languages do
        names.push(nameOfLanguage(code))
    end
    return names
end

## The code of the language called `name` in its own tongue, or nil.
func languageNamed(name)
    for code in i18n.languages do
        if nameOfLanguage(code) == name then
            return code
        end
    end
    return nil
end

## The language of the last run, if it is still one of ours.
func restoreLanguage()
    setLanguage(data.get(i18n.key, i18n.lang))
end

## Picks a language and keeps it for the next run. Says whether it was one of ours.
func chooseLanguage(code)
    if not setLanguage(code) then
        return false
    end
    data.set(i18n.key, code)
    return true
end
