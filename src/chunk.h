#pragma once
#include "opcode.h"
#include "source_loc.h"
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

// Constant-pool key: strict on the tag AND on the raw bits of the union. Do NOT reuse
// ValueEqual (map keys) here — it merges INTEGER(1) with FLOAT(1.0), which would load a value
// of the wrong type. Likewise int 0, float 0.0 and nil share zeroed bits but differ by tag,
// so they must stay distinct entries.
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
    std::vector<SourceLoc> lines; // parallel to code[] — source file+line per instruction
    std::vector<std::string> source_files;
    std::vector<Value> constants;
    std::unordered_map<ConstKey, uint16_t, ConstKeyHash> const_map_; // dédup des constantes
    std::vector<std::string> identifiers;
    std::unordered_map<std::string, uint16_t> identifier_map_;
    std::vector<std::vector<Value>> func_defaults;
    std::vector<FuncProto> funcs;
    uint8_t top_reg_count = 8;
    int current_line_ = 0;
    int current_file_idx_ = 0;

    void set_line(int l, int fi = -1) {
        current_line_ = l;
        if (fi >= 0)
            current_file_idx_ = fi;
    }

    uint16_t add_constant(Value v);
    uint16_t add_identifier(const std::string& name);
    uint16_t add_func_defaults(std::vector<Value> defs);
    uint8_t add_func(FuncProto fp);

    void emit(Instr i);
    size_t emit_jump(Op op, uint8_t a = 0);
    void patch_jump(size_t pos, uint16_t target);
    size_t current_pos() const {
        return code.size();
    }
};
