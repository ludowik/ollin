#include "module_utils.h"
#include "utf8.h"
#include <cctype>
#include <climits>
#include <cmath>

// (int)d est un COMPORTEMENT INDÉFINI (et trappe sur WASM) si d est NaN/inf ou
// hors plage int. On borne le double AVANT le cast ; les contrôles de bornes des
// appelants transforment ensuite un index hors limites en "".
static int toIntSafe(double d) {
    if (std::isnan(d))
        return 0;
    if (d < (double)INT_MIN)
        return INT_MIN;
    if (d > (double)INT_MAX)
        return INT_MAX;
    return (int)d;
}

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

// string.char(s, i) : i-ème CARACTÈRE (codepoint UTF-8), 1-based ; renvoyé sous
// forme de string ; "" si hors limites. (Index par codepoint, pas par octet.)
static Value str_char(Value* args, int argc) {
    const std::string& s = strArg(args, argc, 0, "string.char");
    int i = toIntSafe(numArg(args, argc, 1, "string.char"));
    size_t cnt = utf8Count(s);
    if (i < 1 || (size_t)i > cnt)
        return Value(std::string(""));
    size_t b0 = utf8ByteOffset(s, (size_t)i - 1);
    size_t b1 = utf8ByteOffset(s, (size_t)i);
    return Value(s.substr(b0, b1 - b0));
}

// string.substr(s, start[, length]) : sous-chaîne à partir du caractère start
// (1-based), de length CARACTÈRES (jusqu'à la fin si omis) ; bornes ajustées, ""
// si hors plage. (Comptage par codepoint UTF-8, pas par octet.)
static Value str_substr(Value* args, int argc) {
    const std::string& s = strArg(args, argc, 0, "string.substr");
    size_t cnt = utf8Count(s);
    int start = toIntSafe(numArg(args, argc, 1, "string.substr"));
    int len = (argc >= 3) ? toIntSafe(numArg(args, argc, 2, "string.substr")) : (int)cnt;
    if (start < 1)
        start = 1;
    if (len <= 0 || (size_t)start > cnt)
        return Value(std::string(""));
    size_t startCp = (size_t)start - 1;
    size_t endCp = startCp + (size_t)len; // borné à cnt ci-dessous
    if (endCp > cnt)
        endCp = cnt;
    size_t b0 = utf8ByteOffset(s, startCp);
    size_t b1 = utf8ByteOffset(s, endCp);
    return Value(s.substr(b0, b1 - b0));
}

Value makeStringModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("upper")), Value::makeBuiltin(str_upper));
    m.mapSet(Value(std::string("lower")), Value::makeBuiltin(str_lower));
    m.mapSet(Value(std::string("trim")), Value::makeBuiltin(str_trim));
    m.mapSet(Value(std::string("ltrim")), Value::makeBuiltin(str_ltrim));
    m.mapSet(Value(std::string("rtrim")), Value::makeBuiltin(str_rtrim));
    m.mapSet(Value(std::string("char")), Value::makeBuiltin(str_char));
    m.mapSet(Value(std::string("substr")), Value::makeBuiltin(str_substr));
    return m;
}