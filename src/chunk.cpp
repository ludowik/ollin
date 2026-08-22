#include "chunk.h"
#include <cstring>
#include <stdexcept>

uint16_t Chunk::add_constant(Value v) {
    // Strict per-type dedup on (tag, raw union bytes): one pool entry per distinct literal.
    uint64_t bits;
    std::memcpy(&bits, &v.ival, sizeof(bits)); // the union's bit pattern, which is well defined
    ConstKey key{v.tag, bits};
    auto it = const_map_.find(key);
    if (it != const_map_.end())
        return it->second; // v, the duplicate, is released here, which balances the string's refcount
    if (constants.size() >= 0xFFFF)
        throw std::runtime_error("compile: too many constants (max 65535)");
    uint16_t idx = static_cast<uint16_t>(constants.size());
    constants.push_back(std::move(v));
    const_map_[key] = idx;
    return idx;
}

uint16_t Chunk::add_identifier(const std::string& name) {
    auto it = identifier_map_.find(name);
    if (it != identifier_map_.end())
        return it->second;
    if (identifiers.size() >= 0xFFFF)
        throw std::runtime_error("compile: too many identifiers (max 65535)");
    uint16_t idx = static_cast<uint16_t>(identifiers.size());
    identifiers.push_back(name);
    identifier_map_[name] = idx;
    return idx;
}

uint16_t Chunk::add_func_defaults(std::vector<Value> defs) {
    if (func_defaults.size() >= 0xFFFF)
        throw std::runtime_error("compile: too many functions with defaults (max 65535)");
    func_defaults.push_back(std::move(defs));
    return static_cast<uint16_t>(func_defaults.size() - 1);
}

uint8_t Chunk::add_func(FuncProto fp) {
    if (funcs.size() >= 0xFF)
        throw std::runtime_error("compile: too many functions (max 255)");
    funcs.push_back(std::move(fp));
    return static_cast<uint8_t>(funcs.size() - 1);
}

void Chunk::emit(Instr i) {
    code.push_back(i);
    lines.push_back({(uint16_t)current_file_idx_, (uint16_t)current_line_});
}

size_t Chunk::emit_jump(Op op, uint8_t a) {
    code.push_back(make_abx((uint8_t)op, a, 0xFFFF));
    lines.push_back({(uint16_t)current_file_idx_, (uint16_t)current_line_});
    return code.size() - 1;
}

void Chunk::patch_jump(size_t pos, uint16_t target) {
    Instr old = code[pos];
    code[pos] = (old & 0xFFFF0000u) | target;
}
