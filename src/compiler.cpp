#include "compiler.h"
#include <stdexcept>

Chunk Compiler::compile(const Program& prog) {
    for (auto& s : prog.stmts)
        compileStmt(*s);
    chunk.emit(Op::HALT);
    return std::move(chunk);
}

void Compiler::compileStmt(const Stmt& s) {
    if (auto* v = dynamic_cast<const VarDeclStmt*>(&s))
        compileVarDecl(*v);
    else if (auto* e = dynamic_cast<const ExprStmt*>(&s))
        compileExprStmt(*e);
    else
        throw std::runtime_error("unknown statement type");
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

void Compiler::compileExprStmt(const ExprStmt& s) {
    compileExpr(*s.expr);
}

void Compiler::compileExpr(const Expr& e) {
    if (auto* n = dynamic_cast<const NumberExpr*>(&e)) {
        chunk.emitU16(Op::LOAD_CONST, chunk.addConstant(n->value));
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
