## Regression tests — The webcam module without a browser.
## Run: ./build/ollin tests/regressions/modules/webcam.ol — it must finish without error.
## Only the playground has a webcam; elsewhere the module exists, says it is closed, and refuses the rest.

assert(webcam.isOpen() == false)

var camMsg = "webcam: only available in the playground (WASM)"
var camErr = nil
try
    webcam.open()
catch e
    camErr = e
end
assert(camErr == camMsg)

camErr = nil
try
    webcam.capture()
catch e
    camErr = e
end
assert(camErr == camMsg)

camErr = nil
try
    webcam.close()
catch e
    camErr = e
end
assert(camErr == camMsg)
assert(webcam.isOpen() == false)
