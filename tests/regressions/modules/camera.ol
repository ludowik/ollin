## Regression tests — The camera module without a browser.
## Run: ./build/ollin tests/regressions/modules/camera.ol — it must finish without error.
## Only the playground has a camera; elsewhere the module exists, says it is closed, and refuses the rest.

assert(camera.isOpen() == false)

var camMsg = "camera: only available in the playground (WASM)"
var camErr = nil
try
    camera.open()
catch e
    camErr = e
end
assert(camErr == camMsg)

camErr = nil
try
    camera.capture()
catch e
    camErr = e
end
assert(camErr == camMsg)

camErr = nil
try
    camera.close()
catch e
    camErr = e
end
assert(camErr == camMsg)
assert(camera.isOpen() == false)
