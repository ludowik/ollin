## Regression tests — The display modules in a build without graphics.
## Run: ./build/ollin tests/regressions/modules/display.ol — it must finish without error.
## `tests/run.sh` runs the headless build, where these modules are nil: a script that names one must
## still run, and can test for it. The modules that are NOT nil there (ui, camera) have their own file.

assert(graphics == nil)
assert(keyboard == nil)
assert(mouse == nil)
assert(blend == nil)
assert(image == nil)
assert(typeof(graphics) == "nil")
