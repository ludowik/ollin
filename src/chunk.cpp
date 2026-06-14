#include "chunk.h"
#include <algorithm>
#include <stdexcept>

uint16_t Chunk::addConstant(Value v) {
    if (constants.size() >= 0xFFFF)
        throw std::runtime_error("compile: too many constants (max 65535)");
    constants.push_back(std::move(v));
    return static_cast<uint16_t>(constants.size() - 1);
}

uint16_t Chunk::addIdentifier(const std::string& name) {
    auto it = std::find(identifiers.begin(), identifiers.end(), name);
    if (it != identifiers.end())
        return static_cast<uint16_t>(it - identifiers.begin());
    if (identifiers.size() >= 0xFFFF)
        throw std::runtime_error("compile: too many identifiers (max 65535)");
    identifiers.push_back(name);
    return static_cast<uint16_t>(identifiers.size() - 1);
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
}

size_t Chunk::emitJump(Op op, uint8_t a) {
    // emit placeholder with Bx=0xFFFF
    code.push_back(makeABx((uint8_t)op, a, 0xFFFF));
    return code.size() - 1;  // return index into code[] for patching
}

void Chunk::patchJump(size_t pos, uint16_t target) {
    // patch the lower 16 bits (Bx) of the instruction at pos
    Instr old = code[pos];
    code[pos] = (old & 0xFFFF0000u) | target;
}
