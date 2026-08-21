#include "data_module.h"
#include "value.h"
#include <cstdio>
#include <map>
#include <stdexcept>
#include <string>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// Two scopes: PROJECT, isolated per project, and GLOBAL, shared across projects. Values live in
// memory during the run, encoded and typed, and every write is persisted immediately
// (write-through). Each scope's blob is loaded at the start of the run by the host (data_load).

enum Scope { S_PROJECT = 0, S_GLOBAL = 1 };

static std::map<std::string, std::string> s_store[2];   // [portée] : clé → valeur encodée
#ifndef __EMSCRIPTEN__
static std::string s_file[2];                            // natif : fichier sidecar par portée
#endif

// Typed encoding of a scalar Value to and from the stored string.
// 'i'<entier>, 'f'<double>, 's'<brut>, 'b'<0|1>.
// The 'b' prefix came with the boolean becoming a type of its own: `true` no longer being the
// integer 1, it fell into the throw and data.set("flag", true) failed on a message that promised
// booleans. A value written EARLIER as 'i1' reads back as an integer — which is what it was, and
// scripts test it for truth (if v), so nothing breaks.
static std::string encode_value(const Value& v) {
    if (v.is_bool())
        return std::string("b") + (v.as_bool() ? "1" : "0");
    if (v.is_integer())
        return std::string("i") + std::to_string(v.as_int());
    if (v.is_float()) {
        char buf[32];
        snprintf(buf, sizeof(buf), "f%.17g", v.as_float());
        return buf;
    }
    if (v.is_string())
        return std::string("s") + v.as_string();
    throw std::runtime_error("data: value must be a number, string or boolean");
}
static Value decode_value(const std::string& enc) {
    if (enc.empty())
        return Value();
    std::string rest = enc.substr(1);
    if (enc[0] == 'i')
        return Value((int64_t)std::stoll(rest));
    if (enc[0] == 'f')
        return Value(std::stod(rest));
    if (enc[0] == 'b')
        return Value::make_bool(rest == "1");
    return Value(rest);   // 's' : chaîne brute
}

// Serializing a scope to and from a flat JSON object {key: value}.
static void json_escape(const std::string& s, std::string& out) {
    out += '"';
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if ((unsigned char)c < 0x20) {
                    char b[8];
                    snprintf(b, sizeof(b), "\\u%04x", (unsigned char)c);
                    out += b;
                } else {
                    out += c;   // UTF-8 multi-octets passe tel quel
                }
        }
    }
    out += '"';
}
static std::string serialize(int scope) {
    std::string out = "{";
    bool first = true;
    for (auto& kv : s_store[scope]) {
        if (!first)
            out += ",";
        first = false;
        json_escape(kv.first, out);
        out += ":";
        json_escape(kv.second, out);
    }
    out += "}";
    return out;
}
static bool parse_json_string(const std::string& s, size_t& i, std::string& out) {
    if (i >= s.size() || s[i] != '"')
        return false;
    i++;
    out.clear();
    while (i < s.size()) {
        char c = s[i++];
        if (c == '"')
            return true;
        if (c != '\\') {
            out += c;
            continue;
        }
        if (i >= s.size())
            return false;
        char e = s[i++];
        switch (e) {
            case 'n': out += '\n'; break;
            case 'r': out += '\r'; break;
            case 't': out += '\t'; break;
            case 'u': {
                if (i + 4 > s.size())
                    return false;
                out += (char)std::stoi(s.substr(i, 4), nullptr, 16);   // on n'émet \u que pour < 0x20 (1 octet)
                i += 4;
                break;
            }
            default: out += e; break;   // \" \\ \/ …
        }
    }
    return false;
}
static void deserialize(int scope, const std::string& blob) {
    s_store[scope].clear();
    size_t i = 0;
    auto skip_ws = [&]() {
        while (i < blob.size() && (blob[i] == ' ' || blob[i] == '\n' || blob[i] == '\r' || blob[i] == '\t'))
            i++;
    };
    skip_ws();
    if (i >= blob.size() || blob[i] != '{')
        return;
    i++;
    skip_ws();
    if (i < blob.size() && blob[i] == '}')
        return;
    while (i < blob.size()) {
        skip_ws();
        std::string k, v;
        if (!parse_json_string(blob, i, k))
            return;
        skip_ws();
        if (i >= blob.size() || blob[i] != ':')
            return;
        i++;
        skip_ws();
        if (!parse_json_string(blob, i, v))
            return;
        s_store[scope][k] = v;
        skip_ws();
        if (i < blob.size() && blob[i] == ',') {
            i++;
            continue;
        }
        break;
    }
}

static void persist(int scope) {
#ifdef __EMSCRIPTEN__
    std::string blob = serialize(scope);
    EM_ASM({
        if (window.__ollinData) window.__ollinData.save($0, UTF8ToString($1));
    }, scope, blob.c_str());
#else
    if (s_file[scope].empty())
        return;
    std::string blob = serialize(scope);
    FILE* f = fopen(s_file[scope].c_str(), "wb");
    if (f) {
        fwrite(blob.data(), 1, blob.size(), f);
        fclose(f);
    }
#endif
}

// Shared implementations, parameterized by scope.
static Value data_get(int scope, Value* args, int argc) {
    if (argc < 1 || !args[0].is_string())
        throw std::runtime_error("data.get: expected a string key");
    auto it = s_store[scope].find(args[0].as_string());
    if (it == s_store[scope].end())
        return argc > 1 ? args[1] : Value();
    return decode_value(it->second);
}
static Value data_set(int scope, Value* args, int argc) {
    if (argc < 2 || !args[0].is_string())
        throw std::runtime_error("data.set: expected a string key and a value");
    const std::string& k = args[0].as_string();
    if (args[1].is_nil())
        s_store[scope].erase(k);
    else
        s_store[scope][k] = encode_value(args[1]);
    persist(scope);
    return Value();
}
static Value data_has(int scope, Value* args, int argc) {
    if (argc < 1 || !args[0].is_string())
        throw std::runtime_error("data.has: expected a string key");
    return Value::make_bool(s_store[scope].count(args[0].as_string()) != 0);
}
static Value data_delete(int scope, Value* args, int argc) {
    if (argc < 1 || !args[0].is_string())
        throw std::runtime_error("data.delete: expected a string key");
    s_store[scope].erase(args[0].as_string());
    persist(scope);
    return Value();
}
static Value data_keys(int scope, Value* args, int argc) {
    (void)args; (void)argc;
    Value arr = Value::make_array();
    for (auto& kv : s_store[scope])
        arr.array_push(Value(kv.first));
    return arr;
}
static Value data_clear(int scope, Value* args, int argc) {
    (void)args; (void)argc;
    s_store[scope].clear();
    persist(scope);
    return Value();
}

void data_load(const std::string& project_blob, const std::string& global_blob) {
    deserialize(S_PROJECT, project_blob);
    deserialize(S_GLOBAL, global_blob);
}

#ifndef __EMSCRIPTEN__
static std::string read_file(const std::string& path) {
    FILE* f = fopen(path.c_str(), "rb");
    if (!f)
        return "";
    std::string s;
    char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0)
        s.append(buf, n);
    fclose(f);
    return s;
}
void data_set_native_paths(const std::string& project_file, const std::string& global_file) {
    s_file[S_PROJECT] = project_file;
    s_file[S_GLOBAL] = global_file;
    deserialize(S_PROJECT, read_file(project_file));
    deserialize(S_GLOBAL, read_file(global_file));
}
#endif

// Fills a map with a scope's six operations. The lambdas capture nothing, so they decay to
// function pointers, and the scope is fixed by having one dedicated function per scope.
static void fill_scope(Value& m, int scope) {
    if (scope == S_PROJECT) {
        m.map_set(Value(std::string("get")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_get(S_PROJECT, ctx.args, ctx.argc)); }));
        m.map_set(Value(std::string("set")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_set(S_PROJECT, ctx.args, ctx.argc)); }));
        m.map_set(Value(std::string("has")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_has(S_PROJECT, ctx.args, ctx.argc)); }));
        m.map_set(Value(std::string("delete")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_delete(S_PROJECT, ctx.args, ctx.argc)); }));
        m.map_set(Value(std::string("keys")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_keys(S_PROJECT, ctx.args, ctx.argc)); }));
        m.map_set(Value(std::string("clear")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_clear(S_PROJECT, ctx.args, ctx.argc)); }));
    } else {
        m.map_set(Value(std::string("get")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_get(S_GLOBAL, ctx.args, ctx.argc)); }));
        m.map_set(Value(std::string("set")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_set(S_GLOBAL, ctx.args, ctx.argc)); }));
        m.map_set(Value(std::string("has")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_has(S_GLOBAL, ctx.args, ctx.argc)); }));
        m.map_set(Value(std::string("delete")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_delete(S_GLOBAL, ctx.args, ctx.argc)); }));
        m.map_set(Value(std::string("keys")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_keys(S_GLOBAL, ctx.args, ctx.argc)); }));
        m.map_set(Value(std::string("clear")), Value::make_builtin([](CallCtx& ctx) { return ctx.ret(data_clear(S_GLOBAL, ctx.args, ctx.argc)); }));
    }
}

Value make_data_module() {
    Value m = Value::make_map();
    fill_scope(m, S_PROJECT);
    Value g = Value::make_map();
    fill_scope(g, S_GLOBAL);
    m.map_set(Value(std::string("shared")), g);   // « global » est un mot-clé Ollin → « shared »
    return m;
}
