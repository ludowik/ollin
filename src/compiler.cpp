#include "compiler.h"
#include <stdexcept>

// ── helpers portée ────────────────────────────────────────────────────────────

void Compiler::emitLoadVar(const std::string& name) {
    if (current_func) {
        auto it = current_func->local_ids.find(name);
        if (it != current_func->local_ids.end()) {
            chunk.emitU16(Op::LOAD_LOCAL, it->second);
            return;
        }
    }
    chunk.emitU16(Op::LOAD_VAR, chunk.addIdentifier(name));
}

void Compiler::emitStoreVar(const std::string& name) {
    if (current_func) {
        auto it = current_func->local_ids.find(name);
        int idx;
        if (it == current_func->local_ids.end()) {
            idx = static_cast<int>(current_func->local_ids.size());
            current_func->local_ids[name] = idx;
        } else {
            idx = it->second;
        }
        chunk.emitU16(Op::STORE_LOCAL, idx);
        return;
    }
    chunk.emitU16(Op::STORE_VAR, chunk.addIdentifier(name));
}

Chunk Compiler::compile(const Program& prog) {
    for (auto& s : prog.stmts)
        s->accept(*this);
    chunk.emit(Op::HALT);
    return std::move(chunk);
}

// ── instructions ──────────────────────────────────────────────────────────────

void Compiler::visit(const VarDeclStmt& s) {
    // Cas spécial : appel de fonction utilisateur → multi-retour
    if (s.names.size() > 1 && s.values.size() == 1) {
        if (auto* call = dynamic_cast<const CallExpr*>(s.values[0].get())) {
            if (func_table.count(call->callee)) {
                s.values[0]->accept(*this);
                for (int i = (int)s.names.size() - 1; i >= 0; --i)
                    emitStoreVar(s.names[i]);
                return;
            }
        }
    }
    for (size_t i = 0; i < s.names.size(); ++i) {
        if (i < s.values.size())
            s.values[i]->accept(*this);
        else
            chunk.emitU16(Op::LOAD_CONST, chunk.addConstant(0.0));
        emitStoreVar(s.names[i]);
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
    if (s.op != '\0') emitLoadVar(s.name);
    s.value->accept(*this);
    switch (s.op) {
        case '+': chunk.emit(Op::ADD); break;
        case '-': chunk.emit(Op::SUB); break;
        case '*': chunk.emit(Op::MUL); break;
        case '/': chunk.emit(Op::DIV); break;
        case '\0': break;
        default: throw std::runtime_error(std::string("unknown assign op: ") + s.op);
    }
    emitStoreVar(s.name);
}

void Compiler::visit(const ExprStmt& s) {
    s.expr->accept(*this);
    if (auto* call = dynamic_cast<const CallExpr*>(s.expr.get())) {
        if (func_table.count(call->callee))
            chunk.emit(Op::DISCARD_RETURNS);
    }
}

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
void Compiler::visit(const VarExpr&    e) { emitLoadVar(e.name); }

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
    auto it = func_table.find(e.callee);
    if (it != func_table.end()) {
        const FuncInfo& f = it->second;
        chunk.emitCallFunc(static_cast<uint16_t>(f.addr),
                           static_cast<uint8_t>(f.n_fixed),
                           static_cast<uint8_t>(e.args.size()),
                           f.variadic);
    } else {
        chunk.emitCall(chunk.addIdentifier(e.callee), static_cast<uint8_t>(e.args.size()));
    }
}

void Compiler::visit(const FuncDeclStmt& s) {
    // Enregistre la fonction et saute par-dessus le corps
    FuncInfo info;
    info.n_fixed  = static_cast<int>(s.params.size());
    info.variadic = s.variadic;
    for (int i = 0; i < info.n_fixed; ++i)
        info.local_ids[s.params[i]] = i;

    size_t jump_patch = chunk.emitJump(Op::JUMP);
    info.addr = static_cast<int>(chunk.currentPos());
    func_table[s.name] = info;
    current_func = &func_table[s.name];

    for (auto& stmt : s.body)
        stmt->accept(*this);
    chunk.emitU8(Op::RETURN_N, 0); // return implicite

    current_func = nullptr;
    chunk.patchJump(jump_patch, static_cast<uint16_t>(chunk.currentPos()));
}

void Compiler::visit(const ReturnStmt& s) {
    if (!current_func)
        throw std::runtime_error("return en dehors d'une fonction");
    for (auto& v : s.values)
        v->accept(*this);
    if (s.spread_varargs) {
        chunk.emit(Op::LOAD_VARARGS);
        chunk.emitU8(Op::RETURN_V, static_cast<uint8_t>(s.values.size()));
    } else {
        chunk.emitU8(Op::RETURN_N, static_cast<uint8_t>(s.values.size()));
    }
}

void Compiler::visit(const VarArgExpr&) {
    if (!current_func || !current_func->variadic)
        throw std::runtime_error("... hors d'une fonction variadique");
    chunk.emit(Op::LOAD_VARARGS);
}
