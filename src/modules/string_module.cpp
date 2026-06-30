#include "module_utils.h"
#include <cctype>

static Value str_upper(Value* args, int argc) {
    std::string s = strArg(args, argc, 0, "string.upper");
    for (char& c : s)
        c = (char)std::toupper((unsigned char)c);
    return Value(std::move(s));
}

static Value str_lower(Value* args, int argc) {
    std::string s = strArg(args, argc, 0, "string.lower");
    for (char& c : s)
        c = (char)std::tolower((unsigned char)c);
    return Value(std::move(s));
}

static Value str_trim(Value* args, int argc) {
    const std::string& s = strArg(args, argc, 0, "string.trim");
    const std::string chars = (argc >= 2) ? strArg(args, argc, 1, "string.trim") : " ";
    size_t b = s.find_first_not_of(chars);
    if (b == std::string::npos)
        return Value(std::string(""));
    size_t e = s.find_last_not_of(chars);
    return Value(s.substr(b, e - b + 1));
}

static Value str_ltrim(Value* args, int argc) {
    const std::string& s = strArg(args, argc, 0, "string.ltrim");
    const std::string chars = (argc >= 2) ? strArg(args, argc, 1, "string.ltrim") : " ";
    size_t b = s.find_first_not_of(chars);
    return Value(b == std::string::npos ? std::string("") : s.substr(b));
}

static Value str_rtrim(Value* args, int argc) {
    const std::string& s = strArg(args, argc, 0, "string.rtrim");
    const std::string chars = (argc >= 2) ? strArg(args, argc, 1, "string.rtrim") : " ";
    size_t e = s.find_last_not_of(chars);
    return Value(e == std::string::npos ? std::string("") : s.substr(0, e + 1));
}

// string.char(s, i) : caractère à l'index i (1-based, comme les tableaux),
// renvoyé sous forme de string d'1 caractère ; "" si hors limites.
static Value str_char(Value* args, int argc) {
    const std::string& s = strArg(args, argc, 0, "string.char");
    int i = (int)numArg(args, argc, 1, "string.char");
    if (i < 1 || i > (int)s.size()) return Value(std::string(""));
    return Value(std::string(1, s[i - 1]));
}

// string.substr(s, start[, length]) : sous-chaîne à partir de start (1-based),
// de longueur length (jusqu'à la fin si omis) ; bornes ajustées, "" si hors plage.
static Value str_substr(Value* args, int argc) {
    const std::string& s = strArg(args, argc, 0, "string.substr");
    int start = (int)numArg(args, argc, 1, "string.substr");
    int len   = (argc >= 3) ? (int)numArg(args, argc, 2, "string.substr") : (int)s.size();
    if (start < 1) start = 1;
    if (len <= 0 || start > (int)s.size()) return Value(std::string(""));
    int avail = (int)s.size() - (start - 1);
    if (len > avail) len = avail;
    return Value(s.substr((size_t)(start - 1), (size_t)len));
}

Value makeStringModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("upper")),  Value::makeBuiltin(str_upper));
    m.mapSet(Value(std::string("lower")),  Value::makeBuiltin(str_lower));
    m.mapSet(Value(std::string("trim")),   Value::makeBuiltin(str_trim));
    m.mapSet(Value(std::string("ltrim")),  Value::makeBuiltin(str_ltrim));
    m.mapSet(Value(std::string("rtrim")),  Value::makeBuiltin(str_rtrim));
    m.mapSet(Value(std::string("char")),   Value::makeBuiltin(str_char));
    m.mapSet(Value(std::string("substr")), Value::makeBuiltin(str_substr));
    return m;
}