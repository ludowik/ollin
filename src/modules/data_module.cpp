#include "data_module.h"
#include "value.h"
#include <cstdio>
#include <map>
#include <stdexcept>
#include <string>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// Deux portées : PROJET (isolée par projet) et GLOBALE (partagée entre projets).
// Les valeurs vivent en mémoire pendant le run (encodées, typées) ; chaque écriture
// est persistée immédiatement (write-through). Le blob de chaque portée est chargé
// au début du run par l'hôte (dataLoad).

enum Scope { S_PROJECT = 0, S_GLOBAL = 1 };

static std::map<std::string, std::string> s_store[2];   // [portée] : clé → valeur encodée
#ifndef __EMSCRIPTEN__
static std::string s_file[2];                            // natif : fichier sidecar par portée
#endif

// ── encodage typé d'une Value scalaire ↔ chaîne stockée ────────────────────────
// 'i'<entier>, 'f'<double>, 's'<brut>. (le booléen Ollin est un entier).
static std::string encodeValue(const Value& v) {
    if (v.isInteger())
        return std::string("i") + std::to_string(v.asInt());
    if (v.isFloat()) {
        char buf[32];
        snprintf(buf, sizeof(buf), "f%.17g", v.asFloat());
        return buf;
    }
    if (v.isString())
        return std::string("s") + v.asString();
    throw std::runtime_error("data: value must be a number, string or boolean");
}
static Value decodeValue(const std::string& enc) {
    if (enc.empty())
        return Value();
    std::string rest = enc.substr(1);
    if (enc[0] == 'i')
        return Value((int64_t)std::stoll(rest));
    if (enc[0] == 'f')
        return Value(std::stod(rest));
    return Value(rest);   // 's' : chaîne brute
}

// ── (dé)sérialisation d'une portée en objet JSON plat {clé:valeur} ──────────────
static void jsonEscape(const std::string& s, std::string& out) {
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
        jsonEscape(kv.first, out);
        out += ":";
        jsonEscape(kv.second, out);
    }
    out += "}";
    return out;
}
static bool parseJsonString(const std::string& s, size_t& i, std::string& out) {
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
    auto skipWs = [&]() {
        while (i < blob.size() && (blob[i] == ' ' || blob[i] == '\n' || blob[i] == '\r' || blob[i] == '\t'))
            i++;
    };
    skipWs();
    if (i >= blob.size() || blob[i] != '{')
        return;
    i++;
    skipWs();
    if (i < blob.size() && blob[i] == '}')
        return;
    while (i < blob.size()) {
        skipWs();
        std::string k, v;
        if (!parseJsonString(blob, i, k))
            return;
        skipWs();
        if (i >= blob.size() || blob[i] != ':')
            return;
        i++;
        skipWs();
        if (!parseJsonString(blob, i, v))
            return;
        s_store[scope][k] = v;
        skipWs();
        if (i < blob.size() && blob[i] == ',') {
            i++;
            continue;
        }
        break;
    }
}

// ── persistance write-through ──────────────────────────────────────────────────
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

// ── implémentations partagées (paramétrées par la portée) ───────────────────────
static Value dataGet(int scope, Value* args, int argc) {
    if (argc < 1 || !args[0].isString())
        throw std::runtime_error("data.get: expected a string key");
    auto it = s_store[scope].find(args[0].asString());
    if (it == s_store[scope].end())
        return argc > 1 ? args[1] : Value();
    return decodeValue(it->second);
}
static Value dataSet(int scope, Value* args, int argc) {
    if (argc < 2 || !args[0].isString())
        throw std::runtime_error("data.set: expected a string key and a value");
    const std::string& k = args[0].asString();
    if (args[1].isNil())
        s_store[scope].erase(k);
    else
        s_store[scope][k] = encodeValue(args[1]);
    persist(scope);
    return Value();
}
static Value dataHas(int scope, Value* args, int argc) {
    if (argc < 1 || !args[0].isString())
        throw std::runtime_error("data.has: expected a string key");
    return Value((int64_t)(s_store[scope].count(args[0].asString()) ? 1 : 0));
}
static Value dataDelete(int scope, Value* args, int argc) {
    if (argc < 1 || !args[0].isString())
        throw std::runtime_error("data.delete: expected a string key");
    s_store[scope].erase(args[0].asString());
    persist(scope);
    return Value();
}
static Value dataKeys(int scope, Value* args, int argc) {
    (void)args; (void)argc;
    Value arr = Value::makeArray();
    for (auto& kv : s_store[scope])
        arr.arrayPush(Value(kv.first));
    return arr;
}
static Value dataClear(int scope, Value* args, int argc) {
    (void)args; (void)argc;
    s_store[scope].clear();
    persist(scope);
    return Value();
}

// ── hôte ────────────────────────────────────────────────────────────────────────
void dataLoad(const std::string& projectBlob, const std::string& globalBlob) {
    deserialize(S_PROJECT, projectBlob);
    deserialize(S_GLOBAL, globalBlob);
}

#ifndef __EMSCRIPTEN__
static std::string readFile(const std::string& path) {
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
void dataSetNativePaths(const std::string& projectFile, const std::string& globalFile) {
    s_file[S_PROJECT] = projectFile;
    s_file[S_GLOBAL] = globalFile;
    deserialize(S_PROJECT, readFile(projectFile));
    deserialize(S_GLOBAL, readFile(globalFile));
}
#endif

// Remplit une map avec les 6 opérations d'une portée (lambdas non capturantes →
// pointeurs de fonction ; la portée est figée par une fonction dédiée par portée).
static void fillScope(Value& m, int scope) {
    if (scope == S_PROJECT) {
        m.mapSet(Value(std::string("get")), Value::makeBuiltin([](CallCtx& ctx) { return dataGet(S_PROJECT, ctx.args, ctx.argc); }));
        m.mapSet(Value(std::string("set")), Value::makeBuiltin([](CallCtx& ctx) { return dataSet(S_PROJECT, ctx.args, ctx.argc); }));
        m.mapSet(Value(std::string("has")), Value::makeBuiltin([](CallCtx& ctx) { return dataHas(S_PROJECT, ctx.args, ctx.argc); }));
        m.mapSet(Value(std::string("delete")), Value::makeBuiltin([](CallCtx& ctx) { return dataDelete(S_PROJECT, ctx.args, ctx.argc); }));
        m.mapSet(Value(std::string("keys")), Value::makeBuiltin([](CallCtx& ctx) { return dataKeys(S_PROJECT, ctx.args, ctx.argc); }));
        m.mapSet(Value(std::string("clear")), Value::makeBuiltin([](CallCtx& ctx) { return dataClear(S_PROJECT, ctx.args, ctx.argc); }));
    } else {
        m.mapSet(Value(std::string("get")), Value::makeBuiltin([](CallCtx& ctx) { return dataGet(S_GLOBAL, ctx.args, ctx.argc); }));
        m.mapSet(Value(std::string("set")), Value::makeBuiltin([](CallCtx& ctx) { return dataSet(S_GLOBAL, ctx.args, ctx.argc); }));
        m.mapSet(Value(std::string("has")), Value::makeBuiltin([](CallCtx& ctx) { return dataHas(S_GLOBAL, ctx.args, ctx.argc); }));
        m.mapSet(Value(std::string("delete")), Value::makeBuiltin([](CallCtx& ctx) { return dataDelete(S_GLOBAL, ctx.args, ctx.argc); }));
        m.mapSet(Value(std::string("keys")), Value::makeBuiltin([](CallCtx& ctx) { return dataKeys(S_GLOBAL, ctx.args, ctx.argc); }));
        m.mapSet(Value(std::string("clear")), Value::makeBuiltin([](CallCtx& ctx) { return dataClear(S_GLOBAL, ctx.args, ctx.argc); }));
    }
}

Value makeDataModule() {
    Value m = Value::makeMap();
    fillScope(m, S_PROJECT);
    Value g = Value::makeMap();
    fillScope(g, S_GLOBAL);
    m.mapSet(Value(std::string("shared")), g);   // « global » est un mot-clé Ollin → « shared »
    return m;
}
