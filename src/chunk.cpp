#include "chunk.h"
#include <algorithm>

uint16_t Chunk::addConstant(double v) {
    constants.push_back(v);
    return static_cast<uint16_t>(constants.size() - 1);
}

uint16_t Chunk::addIdentifier(const std::string& name) {
    auto it = std::find(identifiers.begin(), identifiers.end(), name);
    if (it != identifiers.end())
        return static_cast<uint16_t>(it - identifiers.begin());
    identifiers.push_back(name);
    return static_cast<uint16_t>(identifiers.size() - 1);
}

void Chunk::emit(Op op) {
    code.push_back(static_cast<uint8_t>(op));
}

void Chunk::emitU16(Op op, uint16_t arg) {
    code.push_back(static_cast<uint8_t>(op));
    code.push_back(static_cast<uint8_t>(arg >> 8));
    code.push_back(static_cast<uint8_t>(arg & 0xFF));
}

void Chunk::emitCall(uint16_t name_idx, uint8_t argc) {
    code.push_back(static_cast<uint8_t>(Op::CALL));
    code.push_back(static_cast<uint8_t>(name_idx >> 8));
    code.push_back(static_cast<uint8_t>(name_idx & 0xFF));
    code.push_back(argc);
}

size_t Chunk::emitJump(Op op) {
    code.push_back(static_cast<uint8_t>(op));
    code.push_back(0xFF);
    code.push_back(0xFF);
    return code.size() - 2;
}

void Chunk::patchJump(size_t pos, uint16_t target) {
    code[pos]     = static_cast<uint8_t>(target >> 8);
    code[pos + 1] = static_cast<uint8_t>(target & 0xFF);
}
