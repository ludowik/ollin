#pragma once
#include <cstdint>
#include <string>
#include <vector>

// Union taguée 16 octets (vs 32 pour std::variant<double,std::string>)
struct Value {
    enum class Type : uint8_t { Number, String } type;
    union {
        double       n;
        std::string* s;
    };

    Value()                    : type(Type::Number), n(0.0) {}
    Value(double v)            : type(Type::Number), n(v) {}
    Value(std::string v)       : type(Type::String), s(new std::string(std::move(v))) {}

    Value(const Value& o) : type(o.type) {
        if (type == Type::String) s = new std::string(*o.s); else n = o.n;
    }
    Value(Value&& o) noexcept : type(o.type) {
        if (type == Type::String) { s = o.s; o.s = nullptr; }
        else n = o.n;
        o.type = Type::Number; o.n = 0.0;
    }
    Value& operator=(const Value& o) {
        if (this == &o) return *this;
        if (type == Type::String) delete s;
        type = o.type;
        if (type == Type::String) s = new std::string(*o.s); else n = o.n;
        return *this;
    }
    Value& operator=(Value&& o) noexcept {
        if (this == &o) return *this;
        if (type == Type::String) delete s;
        type = o.type;
        if (type == Type::String) { s = o.s; o.s = nullptr; }
        else n = o.n;
        o.type = Type::Number; o.n = 0.0;
        return *this;
    }
    ~Value() { if (type == Type::String) delete s; }

    bool isNumber() const { return type == Type::Number; }
    bool isString() const { return type == Type::String; }
    const std::string& asString() const { return *s; }
};

enum class Op : uint8_t {
    LOAD_CONST,      // uint16 index → constants
    LOAD_VAR,        // uint16 index → identifiers
    STORE_VAR,       // uint16 index → identifiers
    ADD, SUB, MUL, DIV,
    GT, LT,          // pop b,a → push a>b (1.0 ou 0.0)
    EQ,              // pop b,a → push a==b (1.0 ou 0.0)
    JUMP,            // uint16 addr absolu
    JUMP_IF_FALSE,   // uint16 addr absolu ; pop cond
    CALL,            // uint16 name_index, uint8 argc
    TRY,             // uint16 catch_addr  — empile un handler
    POP_TRY,         // dépile le handler  (try body terminé sans throw)
    THROW,           // pop value → saute vers le handler courant
    LOAD_LOCAL,      // uint16 idx → frame.locals
    STORE_LOCAL,     // uint16 idx → frame.locals
    CALL_FUNC,       // uint16 addr, uint8 n_fixed, uint8 argc, uint8 variadic
    RETURN_N,        // uint8 n — retourne n valeurs explicites
    RETURN_V,        // uint8 n — n valeurs explicites + varargs
    LOAD_VARARGS,    // push tous les varargs du frame courant
    DISCARD_RETURNS, // pop ret_count valeurs
    HALT
};

struct Chunk {
    std::vector<uint8_t>   code;
    std::vector<Value>     constants;
    std::vector<std::string> identifiers;

    uint16_t addConstant(Value v);
    uint16_t addIdentifier(const std::string& name);

    void   emit(Op op);
    void   emitU16(Op op, uint16_t arg);
    void   emitU8(Op op, uint8_t arg);
    void   emitCall(uint16_t name_idx, uint8_t argc);
    void   emitCallFunc(uint16_t addr, uint8_t n_fixed, uint8_t argc, bool variadic);
    size_t emitJump(Op op);
    void   patchJump(size_t pos, uint16_t target);
    size_t currentPos() const { return code.size(); }
};
