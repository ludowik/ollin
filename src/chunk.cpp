#include "chunk.h"
#include <stdexcept>

uint16_t Chunk::addConstant(Value v) {
    if (constants.size() >= 0xFFFF)
        throw std::runtime_error("compile: too many constants (max 65535)");
    constants.push_back(std::move(v));
    return static_cast<uint16_t>(constants.size() - 1);
}

uint16_t Chunk::addIdentifier(const std::string& name) {
    auto it = identifier_map_.find(name);
    if (it != identifier_map_.end()) return it->second;
    if (identifiers.size() >= 0xFFFF)
        throw std::runtime_error("compile: too many identifiers (max 65535)");
    uint16_t idx = static_cast<uint16_t>(identifiers.size());
    identifiers.push_back(name);
    identifier_map_[name] = idx;
    return idx;
}

uint16_t Chunk::addFuncDefaults(std::vector<Value> defs) {
    if (func_defaults.size() >= 0xFFFF)
        throw std::runtime_error("compile: too many functions with defaults (max 65535)");
    func_defaults.push_back(std::move(defs));
    return static_cast<uint16_t>(func_defaults.size() - 1);
}

uint8_t Chunk::addFunc(FuncProto fp) {
    if (funcs.size() >= 0xFF)
        throw std::runtime_error("compile: too many functions (max 255)");
    funcs.push_back(fp);
    return static_cast<uint8_t>(funcs.size() - 1);
}

void Chunk::emit(Instr i) {
    code.push_back(i);
    lines.push_back(current_line_);
}

size_t Chunk::emitJump(Op op, uint8_t a) {
    code.push_back(makeABx((uint8_t)op, a, 0xFFFF));
    lines.push_back(current_line_);
    return code.size() - 1;
}

void Chunk::patchJump(size_t pos, uint16_t target) {
    // patch the lower 16 bits (Bx) of the instruction at pos
    Instr old = code[pos];
    code[pos] = (old & 0xFFFF0000u) | target;
}
