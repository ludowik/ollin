## Regression tests — Modules: exporting a module, a library shared under one alias.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/imports.ol — it must finish without error.

## Exporting a module: every kind of declaration must end up in the map `import ... as` creates.
## An enum was missing from it — collect_top_level_names knew nothing of EnumDeclStmt — so
## m.MyEnum was nil.
import "../../exports_test" as expMod
assert(expMod.expVar == 1)
assert(expMod.expGlobal == 2)
assert(expMod.expFunc() == 3)
assert(ExpClass().v == 4)          ## the class is exported, and can be instantiated through the name
assert(expMod.ExpClass <> nil)
assert(expMod.ExpEnum.A == 1 and expMod.ExpEnum.B == 2)
assert(expMod.inAMap == nil)   ## `enum a.b` exports no name of its own


## A library shared by TWO modules, each aliasing it under the same name. A flat import copies a
## module's statements into the importer's scope, so both `var shd = {}` landed here and the
## program was refused with "local variable 'shd' already declared in this scope" — impossible to
## alias a shared library from two modules. The second declaration names the SAME module, so it
## is a no-op and the two importers share the map. Two DIFFERENT modules under one alias stay
## refused, with a message naming both files (test_errors.sh).
import "../../alias_import1_test.ol"
import "../../alias_import2_test.ol"
assert(aliasOne() == 7)
assert(aliasTwo() == 14)
