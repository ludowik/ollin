#include "vm.h"
#include <iostream>
#include <vector>

Value makeColorClass();

static std::string applyFormat(const std::string& fmt, const std::vector<Value>& args, int offset) {
    std::string out;
    int auto_idx = 0;
    for (size_t i = 0; i < fmt.size(); ++i) {
        if (fmt[i] == '{') {
            size_t j = fmt.find('}', i + 1);
            if (j != std::string::npos) {
                std::string spec = fmt.substr(i + 1, j - i - 1);
                int idx;
                if (spec.empty()) {
                    idx = auto_idx++;
                } else {
                    try {
                        idx = std::stoi(spec);
                    } catch (...) {
                        throw std::runtime_error("printf: invalid index '{" + spec + "}'");
                    }
                    if (idx < 0)
                        throw std::runtime_error("printf: index must be >= 0 (got " + spec + ")");
                }
                long long ai = (long long)idx + offset;
                if (ai >= 0 && ai < (long long)args.size())
                    out += valueToString(args[(int)ai]);
                i = j;
                continue;
            }
        }
        out += fmt[i];
    }
    return out;
}

static Value core_print(Value* args, int argc) {
    for (int i = 0; i < argc; ++i) {
        if (i)
            std::cout << ' ';
        std::cout << valueToString(args[i]);
    }
    std::cout << '\n';
    return Value{};
}

static Value core_printf(Value* args, int argc) {
    if (argc < 1 || !args[0].isString())
        throw std::runtime_error("printf: first arg must be string");
    std::vector<Value> vargs(args, args + argc);
    std::cout << applyFormat(args[0].asString(), vargs, 1) << '\n';
    return Value{};
}

static Value core_typeof(Value* args, int argc) {
    if (argc < 1)
        return Value(std::string("nil"));
    return Value(std::string(args[0].typeName()));
}

Value makeCoreModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("print")), Value::makeBuiltin(core_print));
    m.mapSet(Value(std::string("printf")), Value::makeBuiltin(core_printf));
    m.mapSet(Value(std::string("typeof")), Value::makeBuiltin(core_typeof));
    m.mapSet(Value(std::string("Color")), makeColorClass());
    return m;
}
