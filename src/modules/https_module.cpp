#include "https_module.h"
#include "https_internal.h"
#include "module_utils.h"
#include "utf8.h"
#include "value.h"
#include "vm.h"
#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <deque>
#include <stdexcept>
#include <string>
#include <vector>

// The requests in flight, the arguments, and the delivery of the answers. Who talks to the network is
// the engine's business (https_internal.h).
//
// The answers are delivered on the main thread, between two frames: a callback is ordinary script code.
//
// REENTRANCE — a callback may start another request, which grows s_reqs, so (as for tween and ui):
//  - a request is named by {slot, gen}, never by a pointer; `gen` goes up when the slot is freed, so a
//    handle kept after the answer is recognised as finished instead of designating the request that
//    took the slot;
//  - no reference into s_reqs is kept across a call to script code;
//  - the answers are all collected first, the callbacks run afterwards, one by one from a queue: a callback
//    that raises an error leaves the answers behind it in the queue for the next delivery instead of losing
//    them, and a request cancelled while its answer waits there is still cancelled (its slot stays alive
//    until the callback is about to run).

namespace {

constexpr int k_max_inflight = 32;
constexpr double k_default_timeout = 30.0;   // seconds
constexpr double k_max_timeout = 600.0;
constexpr size_t k_max_url = 8192;

struct Req {
    bool alive = false;
    uint32_t gen = 1;
    int id = 0;        // the engine's name for it
    Value callback;
};

std::vector<Req> s_reqs;
std::vector<int> s_free;
std::deque<std::pair<int, Value>> s_ready;   // (request id, response) of the answers not yet delivered
int s_next_id = 1;   // never reset: an answer from before a reset must not meet a new request
bool s_engine_driven = false;

int inflight() {
    int n = 0;
    for (auto& r : s_reqs) {
        if (r.alive)
            n++;
    }
    return n;
}

void free_req(int slot) {
    Req& r = s_reqs[slot];
    r.alive = false;
    r.callback = Value{};   // lets go of what the callback captured
    r.gen++;
    s_free.push_back(slot);
}

int find_by_id(int id) {
    for (size_t i = 0; i < s_reqs.size(); i++) {
        if (s_reqs[i].alive && s_reqs[i].id == id)
            return (int)i;
    }
    return -1;
}

// ── Arguments ────────────────────────────────────────────────────────────────────────────────────

bool starts_with_nocase(const std::string& s, const char* prefix) {
    size_t n = std::char_traits<char>::length(prefix);
    if (s.size() < n)
        return false;
    for (size_t i = 0; i < n; i++) {
        if (std::tolower((unsigned char)s[i]) != prefix[i])
            return false;
    }
    return true;
}

std::string shown(const std::string& s) {
    return s.size() <= 60 ? s : s.substr(0, 57) + "...";
}

void check_url(const std::string& url, const char* fn) {
    if (starts_with_nocase(url, "http://"))
        throw std::runtime_error(std::string(fn) + ": only https:// addresses are accepted, not http:// ('" +
                                 shown(url) + "')");
    if (!starts_with_nocase(url, "https://"))
        throw std::runtime_error(std::string(fn) + ": expected an address starting with https://, got '" +
                                 shown(url) + "'");
    if (url.size() == 8 || url[8] == '/' || url[8] == '?' || url[8] == '#')
        throw std::runtime_error(std::string(fn) + ": the address has no host ('" + shown(url) + "')");
    if (url.size() > k_max_url)
        throw std::runtime_error(std::string(fn) + ": the address is longer than " + std::to_string(k_max_url) +
                                 " characters");
    for (unsigned char c : url) {
        if (c <= 0x20 || c == 0x7f)
            throw std::runtime_error(std::string(fn) +
                                     ": the address holds a space or a control character; write it with "
                                     "https.urlEncode or https.query");
    }
}

// The characters of a header NAME (RFC 9110, a "token"): the browser refuses any other, and refusing it here
// raises the error at the call instead of losing the header — and the ones after it — on the way.
bool is_token_char(unsigned char c) {
    return std::isalnum(c) || (c < 0x80 && std::strchr("!#$%&'*+-.^_`|~", c) != nullptr && c != 0);
}

void check_header(const std::string& name, const Value& value, const char* fn) {
    if (name.empty())
        throw std::runtime_error(std::string(fn) + ": a header has an empty name");
    for (unsigned char c : name) {
        if (!is_token_char(c))
            throw std::runtime_error(std::string(fn) + ": '" + shown(name) + "' is not a header name");
    }
    if (!value.is_string())
        throw std::runtime_error(std::string(fn) + ": the header '" + name + "' must be a string, got " +
                                 value.type_name());
    // A value is made of characters up to U+00FF, without the control ones (a tab is allowed).
    const std::string& text = value.as_string();
    for (size_t i = 0; i < text.size();) {
        size_t n = 1;
        uint32_t cp = utf8_decode(text, i, &n);
        if (cp == '\n' || cp == '\r')
            throw std::runtime_error(std::string(fn) + ": the header '" + name + "' holds a line break");
        if (cp > 0xFF || (cp < 0x20 && cp != '\t') || cp == 0x7f)
            throw std::runtime_error(std::string(fn) + ": the header '" + name +
                                     "' holds a character that a header cannot carry");
        i += n;
    }
}

// The options map: its keys are the only ones accepted, so that a misspelt option is an error and not a
// setting that silently does nothing.
void read_options(const Value& options, HttpsRequest& rq, const char* fn) {
    std::vector<std::pair<std::string, Value>> entries;
    for (auto& kv : options.mptr->data) {
        if (!kv.first.is_string())
            throw std::runtime_error(std::string(fn) + ": an option name must be a string");
        entries.emplace_back(kv.first.as_string(), kv.second);
    }
    std::sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
    for (auto& e : entries) {
        if (e.first == "headers") {
            if (!e.second.is_map())
                throw std::runtime_error(std::string(fn) + ": headers must be a map, got " + e.second.type_name());
            std::vector<std::pair<std::string, Value>> hs;
            for (auto& kv : e.second.mptr->data) {
                if (!kv.first.is_string())
                    throw std::runtime_error(std::string(fn) + ": a header name must be a string");
                hs.emplace_back(kv.first.as_string(), kv.second);
            }
            std::sort(hs.begin(), hs.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
            for (auto& h : hs) {
                check_header(h.first, h.second, fn);
                rq.headers.emplace_back(h.first, h.second.as_string());
            }
        } else if (e.first == "timeout") {
            double t = num_arg(&e.second, 0, fn);
            if (!(t > 0.0) || t > k_max_timeout)
                throw std::runtime_error(std::string(fn) + ": timeout must be between 0 and " +
                                         std::to_string((int)k_max_timeout) + " seconds");
            rq.timeout_ms = (int)(t * 1000.0);
        } else {
            throw std::runtime_error(std::string(fn) + ": unknown option '" + shown(e.first) +
                                     "' (expected headers or timeout)");
        }
    }
}

// ── Requests ─────────────────────────────────────────────────────────────────────────────────────

Value https_class();

Value make_handle(int slot) {
    Value h = Value::make_map();
    h.map_set(Value(std::string("__class__")), https_class());
    h.map_set(Value(std::string("slot")), Value((int64_t)slot));
    h.map_set(Value(std::string("gen")), Value((int64_t)s_reqs[slot].gen));
    return h;
}

// The handle's slot, or -1 once the request is answered or cancelled. Holding on to the handle of a
// request that has finished is normal, not a mistake.
int handle_slot(const Value& self, const char* fn) {
    // A method taken off its request (`var f = req.cancel`) is called with no receiver at all, and the
    // register that should hold it is then whatever the call left there.
    Value cls = self.is_map() ? self.map_get(Value(std::string("__class__"))) : Value{};
    if (!cls.is_class() || cls.as_map() != https_class().as_map())
        throw std::runtime_error(std::string(fn) + ": expected a request");
    Value slot = self.map_get(Value(std::string("slot")));
    Value gen = self.map_get(Value(std::string("gen")));
    if (!slot.is_integer() || !gen.is_integer())
        throw std::runtime_error(std::string(fn) + ": expected a request");
    int i = (int)slot.as_int();
    if (i < 0 || i >= (int)s_reqs.size() || !s_reqs[i].alive || s_reqs[i].gen != (uint32_t)gen.as_int())
        return -1;
    return i;
}

// get(url [, options], callback)
int https_get(CallCtx& ctx) {
    const char* fn = "https.get";
    const std::string& url = str_arg(ctx.args, ctx.argc, 0, fn);
    int last = ctx.argc - 1;
    if (ctx.argc < 2 || !ctx.args[last].is_callable())
        throw std::runtime_error("https.get: expected (url [, options], callback)");
    if (ctx.argc > 3)
        throw std::runtime_error("https.get: expected (url [, options], callback)");
    HttpsRequest rq;
    rq.url = url;
    rq.method = "GET";
    rq.timeout_ms = (int)(k_default_timeout * 1000.0);
    check_url(url, fn);
    if (ctx.argc == 3) {
        if (!ctx.args[1].is_map())
            throw std::runtime_error("https.get: options must be a map, got " + std::string(ctx.args[1].type_name()));
        read_options(ctx.args[1], rq, fn);
    }
    if (inflight() >= k_max_inflight)
        throw std::runtime_error("https.get: too many requests at once (" + std::to_string(k_max_inflight) + ")");

    int slot;
    if (!s_free.empty()) {
        slot = s_free.back();
        s_free.pop_back();
    } else {
        slot = (int)s_reqs.size();
        s_reqs.emplace_back();
    }
    Req& r = s_reqs[slot];
    r.alive = true;
    r.id = s_next_id++;
    r.callback = ctx.args[last];
    int id = r.id;
    Value handle = make_handle(slot);
    https_engine_start(id, rq);
    return ctx.ret(handle);
}

// ── Answers ──────────────────────────────────────────────────────────────────────────────────────

Value make_response(const HttpsAnswer& a) {
    Value res = Value::make_map();
    res.map_set(Value(std::string("ok")), Value::make_bool(a.sent && a.status >= 200 && a.status <= 299));
    res.map_set(Value(std::string("status")), Value((int64_t)a.status));
    res.map_set(Value(std::string("statusText")), Value(a.status_text));
    Value headers = Value::make_map();
    for (auto& h : a.headers)
        headers.map_set(Value(h.first), Value(h.second));
    res.map_set(Value(std::string("headers")), headers);
    res.map_set(Value(std::string("body")), Value(a.body));
    if (!a.sent)
        res.map_set(Value(std::string("error")), Value(a.error));
    res.map_set(Value(std::string("url")), Value(a.url));
    return res;
}

void deliver() {
    // Nothing in flight, nothing waiting: no answer can have come, and the engine is not asked (in the browser
    // that is a crossing of the JavaScript boundary, which every frame of every program would pay).
    if (s_ready.empty() && inflight() == 0)
        return;
    std::vector<HttpsAnswer> answers;
    https_engine_collect(answers);
    for (auto& a : answers)
        s_ready.emplace_back(a.id, make_response(a));
    while (!s_ready.empty()) {
        std::pair<int, Value> item = std::move(s_ready.front());
        s_ready.pop_front();
        int slot = find_by_id(item.first);
        if (slot < 0)
            continue;   // cancelled meanwhile
        Value cb = s_reqs[slot].callback;
        free_req(slot);
        VM::current()->call_value(cb, item.second);
    }
}

// https.update() delivers by hand, for a program with NO render loop (a test, headless native). It does
// nothing once the engine delivers by itself, so that a call left in draw() cannot run a callback twice.
int https_update(CallCtx& ctx) {
    if (!s_engine_driven)
        deliver();
    return ctx.ret(Value{});
}

// ── Building an address ──────────────────────────────────────────────────────────────────────────

void percent_encode(const std::string& s, std::string& out) {
    static const char* hex = "0123456789ABCDEF";
    for (unsigned char c : s) {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            out += (char)c;
        } else {
            out += '%';
            out += hex[c >> 4];
            out += hex[c & 15];
        }
    }
}

int https_url_encode(CallCtx& ctx) {
    const std::string& text = str_arg(ctx.args, ctx.argc, 0, "https.urlEncode");
    std::string out;
    percent_encode(text, out);
    return ctx.ret(Value(out));
}

// query(url, fields): the fields in the order of their names, since a map has none and the same call must
// give the same address. A nil field is left out.
int https_query(CallCtx& ctx) {
    const char* fn = "https.query";
    std::string url = str_arg(ctx.args, ctx.argc, 0, fn);
    if (ctx.argc < 2 || !ctx.args[1].is_map())
        throw std::runtime_error("https.query: expected (url, fields)");
    // The fields go before a fragment (#…): fetch never sends what follows it, so a query put after it is lost.
    std::string fragment;
    size_t hash = url.find('#');
    if (hash != std::string::npos) {
        fragment = url.substr(hash);
        url.resize(hash);
    }
    if (url.empty())
        throw std::runtime_error("https.query: the address is empty");
    std::vector<std::pair<std::string, Value>> fields;
    for (auto& kv : ctx.args[1].mptr->data) {
        if (!kv.first.is_string())
            throw std::runtime_error("https.query: a field name must be a string");
        fields.emplace_back(kv.first.as_string(), kv.second);
    }
    std::sort(fields.begin(), fields.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
    char sep = url.find('?') == std::string::npos ? '?' : '&';
    if (url.back() == '?' || url.back() == '&')
        sep = 0;
    for (auto& f : fields) {
        const Value& v = f.second;
        if (!(v.is_string() || v.is_integer() || v.is_float() || v.is_bool()))
            throw std::runtime_error("https.query: the field '" + shown(f.first) + "' must be a string, a number or a boolean, got " +
                                     v.type_name());
        if (sep)
            url += sep;
        sep = '&';
        percent_encode(f.first, url);
        url += '=';
        percent_encode(v.is_string() ? v.as_string() : value_to_string_plain(v), url);
    }
    return ctx.ret(Value(url + fragment));
}

// ── Request methods ──────────────────────────────────────────────────────────────────────────────
// CALL_METHOD puts the receiver in args[0] for an instance.

int method_cancel(CallCtx& ctx) {
    if (ctx.argc < 1)
        throw std::runtime_error("request.cancel: expected a request");
    int slot = handle_slot(ctx.args[0], "request.cancel");
    if (slot >= 0) {
        https_engine_cancel(s_reqs[slot].id);
        free_req(slot);
    }
    return ctx.ret(Value{});
}

int method_done(CallCtx& ctx) {
    if (ctx.argc < 1)
        throw std::runtime_error("request.done: expected a request");
    return ctx.ret(Value::make_bool(handle_slot(ctx.args[0], "request.done") < 0));
}

Value make_https_class() {
    return MapBuilder(Value::make_class())
        .str("__name__", "Request")
        .fn("cancel", method_cancel)
        .fn("done", method_done)
        .done();
}

Value https_class() {
    static Value cls = make_https_class();
    return cls;
}

} // namespace

void https_poll() {
    s_engine_driven = true;   // the engine delivers, so https.update becomes a no-op on the script side
    deliver();
}

void https_reset() {
    https_engine_reset();
    s_ready.clear();
    s_reqs.clear();
    s_free.clear();
    s_engine_driven = false;
}

Value make_https_module() {
    return MapBuilder()
        .fn("get", https_get)
        .fn("update", https_update)
        .fn("urlEncode", https_url_encode)
        .fn("query", https_query)
        .done();
}
