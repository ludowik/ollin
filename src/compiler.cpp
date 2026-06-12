#include "compiler.h"
#include <stdexcept>

Chunk Compiler::compile(const Program& prog) {
    for (auto& s : prog.stmts)
        s->accept(*this);
    chunk.emit(Op::HALT);
    return std::move(chunk);
}

// ── instructions ──────────────────────────────────────────────────────────────

void Compiler::visit(const VarDeclStmt& s) {
    for (size_t i = 0; i < s.names.size(); ++i) {
        if (i < s.values.size())
            s.values[i]->accept(*this);
        else
            chunk.emitU16(Op::LOAD_CONST, chunk.addConstant(0.0));
        chunk.emitU16(Op::STORE_VAR, chunk.addIdentifier(s.names[i]));
    }
}

void Compiler::visit(const WhileStmt& s) {
    auto loop_start = static_cast<uint16_t>(chunk.currentPos());
    s.cond->accept(*this);
    size_t exit_patch = chunk.emitJump(Op::JUMP_IF_FALSE);

    break_patches.push_back({});
    for (auto& stmt : s.body)
        stmt->accept(*this);
    chunk.emitU16(Op::JUMP, loop_start);

    auto exit_target = static_cast<uint16_t>(chunk.currentPos());
    chunk.patchJump(exit_patch, exit_target);
    for (size_t p : break_patches.back())
        chunk.patchJump(p, exit_target);
    break_patches.pop_back();
}

void Compiler::visit(const IfStmt& s) {
    std::vector<size_t> end_patches;
    s.cond->accept(*this);
    size_t next_patch = chunk.emitJump(Op::JUMP_IF_FALSE);
    for (auto& stmt : s.then_body) stmt->accept(*this);
    end_patches.push_back(chunk.emitJump(Op::JUMP));
    for (auto& ei : s.else_ifs) {
        chunk.patchJump(next_patch, static_cast<uint16_t>(chunk.currentPos()));
        ei.cond->accept(*this);
        next_patch = chunk.emitJump(Op::JUMP_IF_FALSE);
        for (auto& stmt : ei.body) stmt->accept(*this);
        end_patches.push_back(chunk.emitJump(Op::JUMP));
    }
    chunk.patchJump(next_patch, static_cast<uint16_t>(chunk.currentPos()));
    for (auto& stmt : s.else_body) stmt->accept(*this);
    uint16_t end_addr = static_cast<uint16_t>(chunk.currentPos());
    for (size_t p : end_patches) chunk.patchJump(p, end_addr);
}

void Compiler::visit(const BreakStmt&) {
    if (break_patches.empty())
        throw std::runtime_error("line 0: break outside loop");
    break_patches.back().push_back(chunk.emitJump(Op::JUMP));
}

void Compiler::visit(const AssignStmt& s) {
    if (s.op != '\0')
        chunk.emitU16(Op::LOAD_VAR, chunk.addIdentifier(s.name));
    s.value->accept(*this);
    switch (s.op) {
        case '+': chunk.emit(Op::ADD); break;
        case '-': chunk.emit(Op::SUB); break;
        case '*': chunk.emit(Op::MUL); break;
        case '/': chunk.emit(Op::DIV); break;
        case '\0': break;
        default: throw std::runtime_error(std::string("unknown assign op: ") + s.op);
    }
    chunk.emitU16(Op::STORE_VAR, chunk.addIdentifier(s.name));
}

void Compiler::visit(const ExprStmt& s) { s.expr->accept(*this); }

void Compiler::visit(const ThrowStmt& s) {
    s.value->accept(*this);
    chunk.emit(Op::THROW);
}

void Compiler::visit(const TryCatchStmt& s) {
    // TRY  ← sera patché avec l'adresse du catch
    size_t try_patch = chunk.emitJump(Op::TRY);

    for (auto& stmt : s.try_body)
        stmt->accept(*this);

    // try body terminé sans throw : dépile le handler, saute vers else
    chunk.emit(Op::POP_TRY);
    size_t else_patch = chunk.emitJump(Op::JUMP);

    // ── catch block ──
    uint16_t catch_addr = static_cast<uint16_t>(chunk.currentPos());
    chunk.patchJump(try_patch, catch_addr);

    chunk.emitU16(Op::STORE_VAR, chunk.addIdentifier(s.catch_var));
    for (auto& stmt : s.catch_body)
        stmt->accept(*this);
    size_t end_patch = chunk.emitJump(Op::JUMP);

    // ── else block ──
    uint16_t else_addr = static_cast<uint16_t>(chunk.currentPos());
    chunk.patchJump(else_patch, else_addr);

    for (auto& stmt : s.else_body)
        stmt->accept(*this);

    // ── end ──
    uint16_t end_addr = static_cast<uint16_t>(chunk.currentPos());
    chunk.patchJump(end_patch, end_addr);
}

// ── expressions ───────────────────────────────────────────────────────────────

void Compiler::visit(const NumberExpr& e) { chunk.emitU16(Op::LOAD_CONST, chunk.addConstant(e.value)); }
void Compiler::visit(const StringExpr& e) { chunk.emitU16(Op::LOAD_CONST, chunk.addConstant(e.value)); }
void Compiler::visit(const BoolExpr&   e) { chunk.emitU16(Op::LOAD_CONST, chunk.addConstant(e.value ? 1.0 : 0.0)); }
void Compiler::visit(const VarExpr&    e) { chunk.emitU16(Op::LOAD_VAR,   chunk.addIdentifier(e.name)); }

void Compiler::visit(const BinaryExpr& e) {
    e.left->accept(*this);
    e.right->accept(*this);
    switch (e.op) {
        case '+': chunk.emit(Op::ADD); break;
        case '-': chunk.emit(Op::SUB); break;
        case '*': chunk.emit(Op::MUL); break;
        case '/': chunk.emit(Op::DIV); break;
        case '>': chunk.emit(Op::GT);  break;
        case '<': chunk.emit(Op::LT);  break;
        case '=': chunk.emit(Op::EQ);  break;
        default:  throw std::runtime_error(std::string("unknown operator: ") + e.op);
    }
}

void Compiler::visit(const CallExpr& e) {
    for (auto& arg : e.args)
        arg->accept(*this);
    chunk.emitCall(chunk.addIdentifier(e.callee), static_cast<uint8_t>(e.args.size()));
}
