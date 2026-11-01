## Regression tests — The https module (the build without a browser: its engine answers "unsupported").
## Run: ./build/ollin tests/regressions/modules/https.ol — it must finish without error.
## What reaches a server is the browser's business and is tried in the browser; what is checked here is
## everything around it: the arguments, the requests in flight, the callbacks.

## Catches an error and returns its message, nil when there is none.
func failure(f)
    var message = nil
    try
        f()
    catch e
        message = e
    end
    return message
end

func ignore(res)
end

## ── A request, its answer, and its handle ──────────────────────────────────
var seen = []
var req = https.get("https://example.org/data", func(res)
    seen.push(res)
end)
assert(req.done() == false, "the answer has not been delivered yet")
assert(len(seen) == 0, "the callback never runs inside the call that made the request")
https.update()
assert(len(seen) == 1 and req.done() == true)
var res = seen[1]
assert(res.ok == false and res.status == 0 and res.body == "" and res.error == "unsupported")
assert(res.url == "https://example.org/data" and res.statusText == "" and len(res.headers) == 0)
https.update()
assert(len(seen) == 1, "an answer is delivered once")
req.cancel()
assert(req.done() == true, "cancelling a finished request is harmless")

## ── Cancelling ─────────────────────────────────────────────────────────────
var ran = 0
var cancelled = https.get("https://example.org/a", func(r)
    ran += 1
end)
var kept = https.get("https://example.org/b", func(r)
    ran += 10
end)
cancelled.cancel()
assert(cancelled.done() == true and kept.done() == false)
https.update()
assert(ran == 10, "only the request that was not cancelled is answered")

## ── The answers come in the order of the requests ──────────────────────────
var order = []
for i = 1, 5 do
    https.get("https://example.org/{i}", func(r)
        order.push(r.url)
    end)
end
https.update()
assert(len(order) == 5 and order[1] == "https://example.org/1" and order[5] == "https://example.org/5")

## ── A callback may start a request, which is answered at the next delivery ─
var chain = []
var first = nil
first = https.get("https://example.org/first", func(r)
    chain.push("first")
    https.get("https://example.org/second", func(r2)
        chain.push("second")
    end)
end)
https.update()
assert(len(chain) == 1 and chain[1] == "first", "the request made by a callback waits for the next delivery")
assert(first.done() == true)
https.update()
assert(len(chain) == 2 and chain[2] == "second")

## A slot freed by an answer is reused, and the old handle must not designate the new request.
var old = https.get("https://example.org/old", ignore)
https.update()
var new = https.get("https://example.org/new", func(r)
    chain.push("new")
end)
assert(old.done() == true and new.done() == false, "a stale handle is not the request that took its slot")
old.cancel()
https.update()
assert(chain[len(chain)] == "new", "cancelling through a stale handle did nothing")

## ── A callback that raises an error does not make the other answers vanish ──
var delivered = []
var bad = https.get("https://example.org/bad", func(r)
    throw "boom"
end)
var after = https.get("https://example.org/after", func(r)
    delivered.push("after")
end)
var dropped = https.get("https://example.org/dropped", func(r)
    delivered.push("dropped")
end)
assert(failure(func() https.update() end) == "boom", "the error reaches the caller of the delivery")
assert(len(delivered) == 0 and bad.done() == true and after.done() == false, "the answer behind it waits")
dropped.cancel()
assert(dropped.done() == true, "a request whose answer is waiting can still be cancelled")
https.update()
assert(len(delivered) == 1 and delivered[1] == "after", "the next delivery runs what was left, minus what was cancelled")
assert(after.done() == true)

## ── Options ────────────────────────────────────────────────────────────────
var optionsRan = 0
https.get("https://example.org/o", {headers: {Accept: "application/json", "X-Key": "k"}, timeout: 5}, func(r)
    optionsRan += 1
end)
https.get("https://example.org/o", {}, func(r)
    optionsRan += 1
end)
https.update()
assert(optionsRan == 2)

assert(failure(func() https.get("https://example.org", {timeout: 0}, ignore) end) ==
       "https.get: timeout must be between 0 and 600 seconds")
assert(failure(func() https.get("https://example.org", {timeout: 601}, ignore) end) ==
       "https.get: timeout must be between 0 and 600 seconds")
assert(failure(func() https.get("https://example.org", {timeout: "5"}, ignore) end) ==
       "https.get: argument 1 expected number, got string")
assert(failure(func() https.get("https://example.org", {tiemout: 5}, ignore) end) ==
       "https.get: unknown option 'tiemout' (expected headers or timeout)")
assert(failure(func() https.get("https://example.org", {headers: 5}, ignore) end) ==
       "https.get: headers must be a map, got int")
assert(failure(func() https.get("https://example.org", {headers: {A: 5}}, ignore) end) ==
       "https.get: the header 'A' must be a string, got int")
assert(failure(func() https.get("https://example.org", {headers: {"A:B": "x"}}, ignore) end) ==
       "https.get: 'A:B' is not a header name")
assert(failure(func() https.get("https://example.org", {headers: {A: "x" + string.fromCode(10) + "y"}}, ignore) end) ==
       "https.get: the header 'A' holds a line break")
assert(failure(func() https.get("https://example.org", 5, ignore) end) == "https.get: options must be a map, got int")

## ── Addresses ──────────────────────────────────────────────────────────────
assert(failure(func() https.get("http://example.org", ignore) end) ==
       "https.get: only https:// addresses are accepted, not http:// ('http://example.org')")
assert(failure(func() https.get("HTTP://example.org", ignore) end) ==
       "https.get: only https:// addresses are accepted, not http:// ('HTTP://example.org')")
assert(failure(func() https.get("ftp://example.org", ignore) end) ==
       "https.get: expected an address starting with https://, got 'ftp://example.org'")
assert(failure(func() https.get("example.org", ignore) end) ==
       "https.get: expected an address starting with https://, got 'example.org'")
assert(failure(func() https.get("https://", ignore) end) == "https.get: the address has no host ('https://')")
assert(failure(func() https.get("https:///path", ignore) end) == "https.get: the address has no host ('https:///path')")
assert(failure(func() https.get("https://a b", ignore) end) ==
       "https.get: the address holds a space or a control character; write it with https.urlEncode or https.query")
assert(failure(func() https.get("https://example.org/" + string.repeat("x", 9000), ignore) end) ==
       "https.get: the address is longer than 8192 characters")
https.get("HTTPS://Example.org/Path?x=1#top", ignore)
https.update()

## ── The call itself ────────────────────────────────────────────────────────
assert(failure(func() https.get() end) == "https.get: missing argument")
assert(failure(func() https.get(5, ignore) end) == "https.get: expected string")
assert(failure(func() https.get("https://example.org") end) == "https.get: expected (url [, options], callback)")
assert(failure(func() https.get("https://example.org", 5) end) == "https.get: expected (url [, options], callback)")
assert(failure(func() https.get("https://example.org", {}, ignore, 4) end) == "https.get: expected (url [, options], callback)")

## ── Too many at once ───────────────────────────────────────────────────────
var pending = []
for i = 1, 32 do
    pending.push(https.get("https://example.org/{i}", ignore))
end
assert(failure(func() https.get("https://example.org/33", ignore) end) == "https.get: too many requests at once (32)")
pending[1].cancel()
var again = https.get("https://example.org/34", ignore)
assert(again.done() == false, "a cancelled request frees its place")
https.update()
assert(failure(func() https.get("https://example.org/35", ignore) end) == nil, "after the answers, the places are free")
https.update()

## ── Writing an address ─────────────────────────────────────────────────────
assert(https.urlEncode("abc-DEF_0.9~") == "abc-DEF_0.9~", "the unreserved characters stay as they are")
assert(https.urlEncode("a b&c=d/é") == "a%20b%26c%3Dd%2F%C3%A9")
assert(https.urlEncode("") == "")
assert(failure(func() https.urlEncode(5) end) == "https.urlEncode: expected string")

assert(https.query("https://a.b/c", {n: 3, name: "Paris & Co", z: 0.5, ok: true}) ==
       "https://a.b/c?n=3&name=Paris%20%26%20Co&ok=true&z=0.5", "the fields are in the order of their names")
assert(https.query("https://a.b/c?x=1", {y: 2}) == "https://a.b/c?x=1&y=2", "a query already there is continued")
assert(https.query("https://a.b/c?", {y: 2}) == "https://a.b/c?y=2")
assert(https.query("https://a.b/c", {}) == "https://a.b/c")
assert(https.query("https://a.b/c", {x: nil, y: 1}) == "https://a.b/c?y=1", "a nil field is left out")
assert(failure(func() https.query("https://a.b", {x: [1]}) end) ==
       "https.query: the field 'x' must be a string, a number or a boolean, got array")
assert(failure(func() https.query("https://a.b") end) == "https.query: expected (url, fields)")
assert(failure(func() https.query("https://a.b", {[1]: 2}) end) == "https.query: a field name must be a string")

## ── A request handle is a Request ──────────────────────────────────────────
var r = https.get("https://example.org/t", ignore)
assert(r.__class__.__name__ == "Request")
https.update()
