#pragma once
#include "opcode.h"
#include "value.h"
#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

struct UpvalDesc {
    bool is_local; // true = capture local reg from enclosing frame; false = pass through upval
    uint8_t idx;   // register index (is_local) or upvalue index of enclosing closure
};

struct FuncProto {
    uint32_t addr = 0;
    uint8_t n_fixed = 0;
    bool variadic = false;
    bool is_static = false;
    uint16_t defaults_idx = 0;
    uint8_t reg_count = 0;
    std::vector<UpvalDesc> upvals;
};

// Clé de déduplication des constantes : STRICTE par type (tag) + motif binaire de
// l'union. À NE PAS confondre avec ValueEqual (clés de map) qui fusionne
// INTEGER(1) et FLOAT(1.0) → chargerait le mauvais type. De même int 0 / float 0.0
// / nil partagent des bits nuls mais des tags distincts → doivent rester séparés.
struct ConstKey {
    uint8_t tag;
    uint64_t bits;
    bool operator==(const ConstKey& o) const {
        return tag == o.tag && bits == o.bits;
    }
};
struct ConstKeyHash {
    size_t operator()(const ConstKey& k) const {
        return (std::hash<uint64_t>{}(k.bits) * 31u) ^ k.tag;
    }
};

struct Chunk {
    std::vector<Instr> code;
    std::vector<int> lines; // parallel to code[] — source line per instruction
    std::vector<Value> constants;
    std::unordered_map<ConstKey, uint16_t, ConstKeyHash> const_map_; // dédup des constantes
    std::vector<std::string> identifiers;
    std::unordered_map<std::string, uint16_t> identifier_map_;
    std::vector<std::vector<Value>> func_defaults;
    std::vector<FuncProto> funcs;
    uint8_t top_reg_count = 8;
    int current_line_ = 0;

    void setLine(int l) {
        current_line_ = l;
    }

    uint16_t addConstant(Value v);
    uint16_t addIdentifier(const std::string& name);
    uint16_t addFuncDefaults(std::vector<Value> defs);
    uint8_t addFunc(FuncProto fp);

    void emit(Instr i);
    size_t emitJump(Op op, uint8_t a = 0);
    void patchJump(size_t pos, uint16_t target);
    size_t currentPos() const {
        return code.size();
    }
};
