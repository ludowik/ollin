## The language a program speaks (docs/samples/lib/i18n.ol).

import "i18n.ol"
import "i18n_testlib.ol"

useLanguages(["a", "b"], {a: {name: "Aye", hello: "hi"}, b: {name: "Bee", hello: "ho"}}, "i18n_test.lang")

assert(i18n.lang == "a" and tr("hello") == "hi", "the first language is the default")
assert(setLanguage("b") and tr("hello") == "ho")
assert(setLanguage("zz") == false and tr("hello") == "ho", "an unknown language changes nothing")
assert(languageNames()[1] == "Aye" and languageNames()[2] == "Bee" and len(languageNames()) == 2)
assert(languageNamed("Bee") == "b" and languageNamed("Cee") == nil)

assert(chooseLanguage("zz") == false and i18n.lang == "b", "an unknown choice is refused")
assert(chooseLanguage("a") and tr("hello") == "hi")
setLanguage("b")
restoreLanguage()
assert(i18n.lang == "a", "the choice is kept for the next run")

checkLanguages()
print("i18n ok")
