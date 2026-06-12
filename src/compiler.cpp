#include "compiler.h"
#include <stdexcept>

Chunk Compiler::compile(const Program& prog) {
    for (auto& s : prog.stmts)
        compileStmt(*s);
    chunk.emit(Op::HALT);
    return std::move(chunk);
}

void Compiler::compileStmt(const Stmt& s) {
    if      (auto* v = dynamic_cast<const VarDeclStmt*>(&s)) compileVarDecl(*v);
    else if (auto* w = dynamic_cast<const WhileStmt*>(&s))   compileWhileStmt(*w);
    else if (auto* i = dynamic_cast<const IfStmt*>(&s))      compileIfStmt(*i);
    else if (dynamic_cast<const BreakStmt*>(&s))              compileBreakStmt();
    else if (auto* a = dynamic_cast<const AssignStmt*>(&s))   compileAssignStmt(*a);
    else if (auto* e = dynamic_cast<const ExprStmt*>(&s))    compileExprStmt(*e);
    else throw std::runtime_error("unknown statement type");
}

void Compiler::compileVarDecl(const VarDeclStmt& s) {
    for (size_t i = 0; i < s.names.size(); ++i) {
        if (i < s.values.size())
            compileExpr(*s.values[i]);
        else
            chunk.emitU16(Op::LOAD_CONST, chunk.addConstant(0.0));
        chunk.emitU16(Op::STORE_VAR, chunk.addIdentifier(s.names[i]));
    }
}

void Compiler::compileWhileStmt(const WhileStmt& s) {
    auto loop_start = static_cast<uint16_t>(chunk.currentPos());
    compileExpr(*s.cond);
    size_t exit_patch = chunk.emitJump(Op::JUMP_IF_FALSE);

    break_patches.push_back({});
    for (auto& stmt : s.body)
        compileStmt(*stmt);
    chunk.emitU16(Op::JUMP, loop_start);

    auto exit_target = static_cast<uint16_t>(chunk.currentPos());
    chunk.patchJump(exit_patch, exit_target);
    for (size_t p : break_patches.back())
        chunk.patchJump(p, exit_target);
    break_patches.pop_back();
}

void Compiler::compileIfStmt(const IfStmt& s) {
    compileExpr(*s.cond);
    size_t skip_patch = chunk.emitJump(Op::JUMP_IF_FALSE);
    compileStmt(*s.then);
    chunk.patchJump(skip_patch, static_cast<uint16_t>(chunk.currentPos()));
}

void Compiler::compileBreakStmt() {
    if (break_patches.empty())
        throw std::runtime_error("break hors d'une boucle");
    size_t pos = chunk.emitJump(Op::JUMP);
    break_patches.back().push_back(pos);
}

void Compiler::compileAssignStmt(const AssignStmt& s) {
    if (s.op != '\0')
        chunk.emitU16(Op::LOAD_VAR, chunk.addIdentifier(s.name));
    compileExpr(*s.value);
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

void Compiler::compileExprStmt(const ExprStmt& s) {
    compileExpr(*s.expr);
}

void Compiler::compileExpr(const Expr& e) {
    if (auto* n = dynamic_cast<const NumberExpr*>(&e)) {
        chunk.emitU16(Op::LOAD_CONST, chunk.addConstant(n->value));
    } else if (auto* s = dynamic_cast<const StringExpr*>(&e)) {
        chunk.emitU16(Op::LOAD_CONST, chunk.addConstant(s->value));
    } else if (auto* b = dynamic_cast<const BoolExpr*>(&e)) {
        chunk.emitU16(Op::LOAD_CONST, chunk.addConstant(b->value ? 1.0 : 0.0));
    } else if (auto* v = dynamic_cast<const VarExpr*>(&e)) {
        chunk.emitU16(Op::LOAD_VAR, chunk.addIdentifier(v->name));
    } else if (auto* b = dynamic_cast<const BinaryExpr*>(&e)) {
        compileExpr(*b->left);
        compileExpr(*b->right);
        switch (b->op) {
            case '+': chunk.emit(Op::ADD); break;
            case '-': chunk.emit(Op::SUB); break;
            case '*': chunk.emit(Op::MUL); break;
            case '/': chunk.emit(Op::DIV); break;
            case '>': chunk.emit(Op::GT);  break;
            case '<': chunk.emit(Op::LT);  break;
            default:  throw std::runtime_error(std::string("unknown operator: ") + b->op);
        }
    } else if (auto* c = dynamic_cast<const CallExpr*>(&e)) {
        for (auto& arg : c->args)
            compileExpr(*arg);
        chunk.emitCall(chunk.addIdentifier(c->callee),
                       static_cast<uint8_t>(c->args.size()));
    } else {
        throw std::runtime_error("unknown expression type");
    }
}
