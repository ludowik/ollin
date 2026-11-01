#include "https_internal.h"
#include <cstdlib>
#include <cstring>
#include <emscripten.h>

// The engine of the browser build: the browser does all of it — the name lookup, the encryption, the
// certificates, the redirections — and a request is one fetch().
//
// The state lives on the JavaScript side, in window.__ollinHttps:
//   pending  the requests in flight, by id, each with its AbortController and its time limit;
//   done     the answers that have arrived and that nobody has collected yet;
//   cur      the answer being handed over, read field by field.
// An answer is accepted only if its request is STILL in `pending`: cancelling or resetting removes the
// entry first, so an answer that arrives afterwards finds nobody and is dropped.
//
// The credentials are never sent (`credentials: 'omit'`): a request made by a script must not carry the
// cookies of the site that hosts the playground.
//
// No object or array literal at the top level of an EM_ASM block, and no `var a = 1, b = 2`: the block is a
// MACRO argument, and a comma outside parentheses separates arguments.

namespace {

void joined(const HttpsHeaders& headers, std::string& out) {
    for (auto& h : headers) {
        out += h.first;
        out += '\n';
        out += h.second;
        out += '\n';
    }
}

// A string field of the answer being handed over, with its length: a body may hold a NUL.
std::string take_field(const char* name) {
    int len = 0;
    char* p = (char*)EM_ASM_INT(
        {
            var s = String(window.__ollinHttps.cur[UTF8ToString($0)]);
            var bytes = new TextEncoder().encode(s);
            var ptr = _malloc(bytes.length + 1);
            HEAPU8.set(bytes, ptr);
            HEAPU8[ptr + bytes.length] = 0;
            HEAP32[$1 >> 2] = bytes.length;
            return ptr;
        },
        name, &len);
    std::string out;
    if (p) {
        out.assign(p, (size_t)len);
        free(p);
    }
    return out;
}

int take_int(const char* name) {
    return EM_ASM_INT({ return window.__ollinHttps.cur[UTF8ToString($0)] | 0; }, name);
}

} // namespace

void https_engine_start(int id, const HttpsRequest& request) {
    std::string headers;
    joined(request.headers, headers);
    EM_ASM(
        {
            var H = window.__ollinHttps;
            if (!H) {
                H = {};
                H.pending = {};
                H.done = [];
                window.__ollinHttps = H;
            }
            var id = $0;
            var url = UTF8ToString($1);
            var method = UTF8ToString($2);
            var flat = UTF8ToString($3);
            var timeout = $4;
            var parts = flat.length ? flat.split('\n') : [];
            var headers = new Headers();
            try {
                for (var i = 0; i + 1 < parts.length; i += 2)
                    headers.append(parts[i], parts[i + 1]);
            } catch (e) {
            }
            var entry = {};
            entry.ctl = new AbortController();
            entry.timedOut = false;
            H.pending[id] = entry;
            entry.timer = setTimeout(function() {
                entry.timedOut = true;
                entry.ctl.abort();
            }, timeout);
            var finish = function(rec) {
                clearTimeout(entry.timer);
                if (H.pending[id] !== entry)
                    return;
                delete H.pending[id];
                rec.id = id;
                H.done.push(rec);
            };
            var fail = function(e) {
                var rec = {};
                rec.sent = 0;
                rec.status = 0;
                rec.statusText = '';
                rec.url = url;
                rec.headers = '';
                rec.body = '';
                rec.error = entry.timedOut ? 'timeout' : String((e && e.message) || e);
                finish(rec);
            };
            try {
                fetch(url, {method: method, headers: headers, signal: entry.ctl.signal, credentials: 'omit', redirect: 'follow'})
                    .then(function(r) {
                        var flatHeaders = [];
                        r.headers.forEach(function(v, k) {
                            flatHeaders.push(k);
                            flatHeaders.push(v);
                        });
                        return r.text().then(function(t) {
                            var rec = {};
                            rec.sent = 1;
                            rec.status = r.status;
                            rec.statusText = r.statusText;
                            rec.url = r.url;
                            rec.headers = flatHeaders.join('\n');
                            rec.body = t;
                            rec.error = '';
                            finish(rec);
                        });
                    })
                    .catch(fail);
            } catch (e) {
                fail(e);
            }
        },
        id, request.url.c_str(), request.method.c_str(), headers.c_str(), request.timeout_ms);
}

void https_engine_cancel(int id) {
    EM_ASM(
        {
            var H = window.__ollinHttps;
            if (!H)
                return;
            var entry = H.pending[$0];
            if (!entry)
                return;
            delete H.pending[$0];
            clearTimeout(entry.timer);
            entry.ctl.abort();
        },
        id);
}

void https_engine_collect(std::vector<HttpsAnswer>& out) {
    while (EM_ASM_INT({
        var H = window.__ollinHttps;
        if (!H || H.done.length === 0)
            return 0;
        H.cur = H.done.shift();
        return 1;
    })) {
        HttpsAnswer a;
        a.id = take_int("id");
        a.sent = take_int("sent") != 0;
        a.status = take_int("status");
        a.status_text = take_field("statusText");
        a.url = take_field("url");
        a.body = take_field("body");
        a.error = take_field("error");
        std::string flat = take_field("headers");
        size_t i = 0;
        while (i < flat.size()) {
            size_t n = flat.find('\n', i);
            if (n == std::string::npos)
                break;
            size_t v = flat.find('\n', n + 1);
            if (v == std::string::npos)
                break;
            a.headers.emplace_back(flat.substr(i, n - i), flat.substr(n + 1, v - n - 1));
            i = v + 1;
        }
        out.push_back(std::move(a));
    }
}

void https_engine_reset() {
    EM_ASM({
        var H = window.__ollinHttps;
        if (!H)
            return;
        for (var id in H.pending) {
            clearTimeout(H.pending[id].timer);
            H.pending[id].ctl.abort();
        }
        H.pending = {};
        H.done = [];
    });
}
