#include "chunk.h"
#include <cstring>
#include <stdexcept>
#include <string>

PoolIdx Chunk::add_constant(Value v) {
    // Strict per-type dedup on (tag, raw union bytes): one pool entry per distinct literal.
    uint64_t bits;
    std::memcpy(&bits, &v.ival, sizeof(bits)); // the union's bit pattern, which is well defined
    ConstKey key{v.tag, bits};
    auto it = const_map_.find(key);
    if (it != const_map_.end())
        return it->second; // v, the duplicate, is released here, which balances the string's refcount
    if (constants.size() >= k_max_pool)
        throw std::runtime_error("compile: too many constants (max " + std::to_string(k_max_pool) + ")");
    PoolIdx idx = static_cast<PoolIdx>(constants.size());
    constants.push_back(std::move(v));
    const_map_[key] = idx;
    return idx;
}

PoolIdx Chunk::add_identifier(const std::string& name) {
    auto it = identifier_map_.find(name);
    if (it != identifier_map_.end())
        return it->second;
    if (identifiers.size() >= k_max_pool)
        throw std::runtime_error("compile: too many identifiers (max " + std::to_string(k_max_pool) + ")");
    PoolIdx idx = static_cast<PoolIdx>(identifiers.size());
    identifiers.push_back(name);
    identifier_map_[name] = idx;
    return idx;
}

PoolIdx Chunk::add_func_defaults(std::vector<Value> defs) {
    if (func_defaults.size() >= k_max_pool)
        throw std::runtime_error("compile: too many functions with defaults (max " + std::to_string(k_max_pool) + ")");
    func_defaults.push_back(std::move(defs));
    return static_cast<PoolIdx>(func_defaults.size() - 1);
}

FuncIdx Chunk::add_func(FuncProto fp) {
    if (funcs.size() >= k_max_func)
        throw std::runtime_error("compile: too many functions (max " + std::to_string(k_max_func) + ")");
    funcs.push_back(std::move(fp));
    return static_cast<FuncIdx>(funcs.size() - 1);
}

void Chunk::emit(Instr i) {
    // The ceiling is checked HERE, where the address is handed out, like the three pools above:
    // an instruction's address is its index, a jump carries it in a Bx, and a program checked
    // only at the end of the compilation would have every one of its jumps silently truncated
    // first.
    // The last address is kept OUT of reach, because emit_jump uses it as its placeholder: a jump
    // left unpatched must stay distinguishable from one that legitimately targets the end.
    if (code.size() >= k_max_code)
        throw std::runtime_error("compile: program too large (max " + std::to_string(k_max_code) + " instructions)");
    code.push_back(i);
    lines.push_back({(uint16_t)current_file_idx_, (uint16_t)current_line_});
}

size_t Chunk::emit_jump(Op op, uint64_t a) {
    // The target is patched later; k_bx_max is the placeholder, never a reachable address.
    emit(make_abx(op, a, k_bx_max));
    return code.size() - 1;
}

void Chunk::patch_jump(size_t pos, uint64_t target) {
    assert(target <= k_bx_max);
    Instr old = code[pos] & ~(Instr)k_bx_max;
    code[pos] = old | (Instr)target;
}
