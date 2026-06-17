#include "compiler.h"
#include <algorithm>
#include <stdexcept>
#include <unordered_set>

// ── upvalue resolution ────────────────────────────────────────────────────────

int Compiler::resolveUpvalue(const std::string& name) {
    auto it = cur_upval_idx_.find(name);
    if (it != cur_upval_idx_.end()) return it->second;
    if (outer_scopes_.empty()) return -1;
    return resolveUpvalFrom((int)outer_scopes_.size() - 1, name);
}

int Compiler::resolveUpvalFrom(int scope_idx, const std::string& name) {
    OuterScope& scope = outer_scopes_[scope_idx];
    auto local_it = scope.regs.find(name);
    if (local_it != scope.regs.end())
        return captureUpvalChain(scope_idx, true, (uint8_t)local_it->second, name);
    auto uv_it = scope.upval_idx.find(name);
    if (uv_it != scope.upval_idx.end())
        return captureUpvalChain(scope_idx, false, (uint8_t)uv_it->second, name);
    if (scope_idx == 0) return -1;
    int outer_uv = resolveUpvalFrom(scope_idx - 1, name);
    if (outer_uv < 0) return -1;
    return captureUpvalChain(scope_idx, false, (uint8_t)outer_uv, name);
}

int Compiler::captureUpvalChain(int scope_idx, bool is_local, uint8_t idx, const std::string& name) {
    bool cur_is_local = is_local;
    uint8_t cur_idx   = idx;

    // Propagate through intermediate function scopes
    for (int i = scope_idx + 1; i < (int)outer_scopes_.size(); i++) {
        OuterScope& s = outer_scopes_[i];
        auto it = s.upval_idx.find(name);
        if (it != s.upval_idx.end()) {
            cur_idx = (uint8_t)it->second;
            cur_is_local = false;
        } else if (s.func_proto_idx >= 0) {
            int uv_i = (int)chunk.funcs[s.func_proto_idx].upvals.size();
            chunk.funcs[s.func_proto_idx].upvals.push_back({cur_is_local, cur_idx});
            s.upval_idx[name] = uv_i;
            cur_idx = (uint8_t)uv_i;
            cur_is_local = false;
        }
    }

    // Add to current function
    {
        auto it = cur_upval_idx_.find(name);
        if (it != cur_upval_idx_.end()) return it->second;
    }
    if (current_func_idx_ < 0) return -1;  // in main chunk, no FuncProto
    int uv_i = (int)chunk.funcs[current_func_idx_].upvals.size();
    chunk.funcs[current_func_idx_].upvals.push_back({cur_is_local, cur_idx});
    cur_upval_idx_[name] = uv_i;
    return uv_i;
}

// ── constant evaluator (for default parameter values) ─────────────────────────
static Value evalConstant(const Expr& e) {
    if (auto* n = dynamic_cast<const NumberExpr*>(&e)) return numValue(n->value);
    if (auto* s = dynamic_cast<const StringExpr*>(&e)) return Value(s->value);
    if (auto* b = dynamic_cast<const BoolExpr*>(&e))   return Value((int64_t)(b->value ? 1 : 0));
    if (dynamic_cast<const NilExpr*>(&e))               return Value{};
    throw std::runtime_error("default values must be literal constants");
}

// ── arithmetic op helpers ─────────────────────────────────────────────────────
static Op charToOp(char op) {
    switch (op) {
        case '+': return Op::ADD;
        case '-': return Op::SUB;
        case '*': return Op::MUL;
        case '/': return Op::DIV;
        case '%': return Op::MOD;
        default:  throw std::runtime_error(std::string("unknown assign op: ") + op);
    }
}
static Op tokenToOp(TokenType op) {
    switch (op) {
        case TokenType::PLUS_EQUAL:    return Op::ADD;
        case TokenType::MINUS_EQUAL:   return Op::SUB;
        case TokenType::STAR_EQUAL:    return Op::MUL;
        case TokenType::SLASH_EQUAL:   return Op::DIV;
        case TokenType::PERCENT_EQUAL: return Op::MOD;
        default: throw std::runtime_error("unknown compound index assign op");
    }
}

// ── pre-scan locals in a block (for register pre-allocation) ─────────────────
// collect_funcs=true inside function bodies (nested FuncDecls need a local register)
// collect_funcs=false at top level (top-level funcs are accessed via func_table)
static void collectLocals(const std::vector<std::unique_ptr<Stmt>>& stmts,
                          std::vector<std::string>& out,
                          std::unordered_set<std::string>& seen,
                          bool collect_funcs) {
    auto add = [&](const std::string& n) {
        if (seen.insert(n).second) out.push_back(n);
    };
    for (auto& s : stmts) {
        if (auto* v = dynamic_cast<const VarDeclStmt*>(s.get()))
            for (auto& n : v->names) add(n);
        if (collect_funcs)
            if (auto* f = dynamic_cast<const FuncDeclStmt*>(s.get()))
                add(f->name);
        if (auto* f = dynamic_cast<const ForStmt*>(s.get())) {
            add(f->var);
            collectLocals(f->body, out, seen, collect_funcs);
        }
        if (auto* fm = dynamic_cast<const ForMapStmt*>(s.get())) {
            add(fm->key_var);
            add(fm->val_var);
            collectLocals(fm->body, out, seen, collect_funcs);
        }
        if (auto* fi = dynamic_cast<const ForInStmt*>(s.get())) {
            add(fi->val_var);
            collectLocals(fi->body, out, seen, collect_funcs);
        }
        if (auto* w = dynamic_cast<const WhileStmt*>(s.get()))
            collectLocals(w->body, out, seen, collect_funcs);
        if (auto* i = dynamic_cast<const IfStmt*>(s.get())) {
            collectLocals(i->then_body, out, seen, collect_funcs);
            for (auto& ei : i->else_ifs) collectLocals(ei.body, out, seen, collect_funcs);
            collectLocals(i->else_body, out, seen, collect_funcs);
        }
        if (auto* t = dynamic_cast<const TryCatchStmt*>(s.get())) {
            collectLocals(t->try_body, out, seen, collect_funcs);
            if (!t->catch_var.empty()) add(t->catch_var);
            collectLocals(t->catch_body, out, seen, collect_funcs);
            collectLocals(t->else_body, out, seen, collect_funcs);
        }
        if (auto* b = dynamic_cast<const BlockStmt*>(s.get()))
            collectLocals(b->stmts, out, seen, collect_funcs);
    }
}

static void collectLocals(const std::vector<std::unique_ptr<Stmt>>& stmts,
                          std::vector<std::string>& out, bool collect_funcs = true) {
    std::unordered_set<std::string> seen(out.begin(), out.end());
    collectLocals(stmts, out, seen, collect_funcs);
}

// ── compile expression into a specific destination register ──────────────────
void Compiler::compileInto(const Expr& e, int dest) {
    if (auto* n = dynamic_cast<const NumberExpr*>(&e)) {
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)dest,
                           chunk.addConstant(numValue(n->value))));
    } else if (auto* s = dynamic_cast<const StringExpr*>(&e)) {
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)dest,
                           chunk.addConstant(Value(s->value))));
    } else if (auto* b = dynamic_cast<const BoolExpr*>(&e)) {
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)dest,
                           chunk.addConstant(Value((int64_t)(b->value ? 1 : 0)))));
    } else if (dynamic_cast<const NilExpr*>(&e)) {
        chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)dest, 0, 0));
    } else {
        int saved = reg_top_;
        e.accept(*this);
        if (last_reg_ != dest)
            chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)dest, (uint8_t)last_reg_, 0));
        reg_top_ = saved;
    }
}

// ── top-level compile ─────────────────────────────────────────────────────────
Chunk Compiler::compile(const Program& prog) {
    reg_top_ = 0;
    reg_count_ = 8;
    // Pre-scan all top-level var/for declarations → registers (like Lua's local in main chunk)
    // collect_funcs=false: top-level functions are in func_table, not in local registers
    std::vector<std::string> top_locals;
    collectLocals(prog.stmts, top_locals, false);
    for (auto& name : top_locals)
        local_regs_[name] = reg_top_++;
    locals_top_ = reg_top_;
    if (reg_top_ > reg_count_) reg_count_ = reg_top_;

    for (auto& s : prog.stmts)
        s->accept(*this);
    chunk.top_reg_count = (uint8_t)std::max(reg_count_, 8);
    chunk.emit(makeBx((uint8_t)Op::HALT, 0));
    return std::move(chunk);
}

// ── statements ────────────────────────────────────────────────────────────────

void Compiler::visit(const VarDeclStmt& s) {
    // Multi-return from user function call
    if (s.names.size() > 1 && s.values.size() == 1) {
        if (auto* call = dynamic_cast<const CallExpr*>(s.values[0].get())) {
            if (func_table.count(call->callee)) {
                int call_base = reg_top_;
                int argc = (int)call->args.size();
                for (int i = 0; i < argc; ++i) {
                    int target = call_base + i;
                    reg_top_ = target;
                    call->args[i]->accept(*this);
                    if (last_reg_ != target)
                        chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)target,
                                           (uint8_t)last_reg_, 0));
                    reg_top_ = target + 1;
                    if (reg_top_ > reg_count_) reg_count_ = reg_top_;
                }
                const FuncInfo& fi = func_table.at(call->callee);
                chunk.emit(makeABC((uint8_t)Op::CALL_FUNC,
                                   (uint8_t)call_base, fi.func_idx, (uint8_t)argc));
                for (int i = 0; i < (int)s.names.size(); ++i) {
                    int dest = local_regs_.at(s.names[i]);
                    if (call_base + i != dest)
                        chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)dest,
                                           (uint8_t)(call_base + i), 0));
                }
                reg_top_ = call_base;
                return;
            }
        }
    }
    // Normal: compile each value into its pre-allocated local register
    for (int i = 0; i < (int)s.names.size(); ++i) {
        int dest = local_regs_.at(s.names[i]);
        if (i < (int)s.values.size()) {
            compileInto(*s.values[i], dest);
        } else {
            chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)dest, 0, 0));
        }
    }
}

void Compiler::visit(const WhileStmt& s) {
    auto loop_start = (uint16_t)chunk.currentPos();
    int saved = reg_top_;
    s.cond->accept(*this);
    int cond_r = last_reg_;
    size_t exit_patch = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);
    reg_top_ = saved;

    break_patches.push_back({});
    continue_patches.push_back({});
    for (auto& stmt : s.body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }
    // continue → réévaluation de la condition
    for (size_t p : continue_patches.back()) chunk.patchJump(p, loop_start);
    continue_patches.pop_back();
    chunk.emit(makeBx((uint8_t)Op::JUMP, loop_start));
    chunk.patchJump(exit_patch, (uint16_t)chunk.currentPos());
    for (size_t p : break_patches.back()) chunk.patchJump(p, (uint16_t)chunk.currentPos());
    break_patches.pop_back();
}

void Compiler::visit(const IfStmt& s) {
    std::vector<size_t> end_patches;

    int saved = reg_top_;
    s.cond->accept(*this);
    int cond_r = last_reg_;
    reg_top_ = saved;
    size_t next_patch = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);

    for (auto& stmt : s.then_body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }
    end_patches.push_back(chunk.emitJump(Op::JUMP));

    for (auto& ei : s.else_ifs) {
        chunk.patchJump(next_patch, (uint16_t)chunk.currentPos());
        int s2 = reg_top_;
        ei.cond->accept(*this);
        int er = last_reg_;
        reg_top_ = s2;
        next_patch = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)er);
        for (auto& stmt : ei.body) {
            int s3 = reg_top_;
            stmt->accept(*this);
            reg_top_ = s3;
        }
        end_patches.push_back(chunk.emitJump(Op::JUMP));
    }

    chunk.patchJump(next_patch, (uint16_t)chunk.currentPos());
    for (auto& stmt : s.else_body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }

    uint16_t end_addr = (uint16_t)chunk.currentPos();
    for (size_t p : end_patches) chunk.patchJump(p, end_addr);
}

void Compiler::visit(const BreakStmt&) {
    if (break_patches.empty())
        throw std::runtime_error("break outside loop");
    break_patches.back().push_back(chunk.emitJump(Op::JUMP));
}

void Compiler::visit(const ContinueStmt&) {
    if (continue_patches.empty())
        throw std::runtime_error("continue outside loop");
    continue_patches.back().push_back(chunk.emitJump(Op::JUMP));
}

void Compiler::visit(const AssignStmt& s) {
    {
        auto it = local_regs_.find(s.name);
        if (it != local_regs_.end()) {
            int dest = it->second;
            if (s.op == '\0') {
                compileInto(*s.value, dest);
            } else {
                // Compound: rhs is fully evaluated before writing back to dest
                int saved = reg_top_;
                s.value->accept(*this);
                int rhs = last_reg_;
                // Emit op directly into dest — safe: rhs is already in a register
                chunk.emit(makeABC((uint8_t)charToOp(s.op), (uint8_t)dest, (uint8_t)dest, (uint8_t)rhs));
                reg_top_ = saved;
            }
            return;
        }
    }
    // Upvalue
    {
        int uv = resolveUpvalue(s.name);
        if (uv >= 0) {
            int saved = reg_top_;
            if (s.op == '\0') {
                s.value->accept(*this);
                chunk.emit(makeABC((uint8_t)Op::SET_UPVAL, (uint8_t)last_reg_, (uint8_t)uv, 0));
            } else {
                int cur = allocReg();
                chunk.emit(makeABC((uint8_t)Op::GET_UPVAL, (uint8_t)cur, (uint8_t)uv, 0));
                s.value->accept(*this);
                int rhs = last_reg_;
                int res = allocReg();
                if (reg_top_ > reg_count_) reg_count_ = reg_top_;
                chunk.emit(makeABC((uint8_t)charToOp(s.op), (uint8_t)res, (uint8_t)cur, (uint8_t)rhs));
                chunk.emit(makeABC((uint8_t)Op::SET_UPVAL, (uint8_t)res, (uint8_t)uv, 0));
            }
            reg_top_ = saved;
            return;
        }
    }
    // Global scope
    uint16_t gidx = chunk.addIdentifier(s.name);
    int saved = reg_top_;
    if (s.op == '\0') {
        s.value->accept(*this);
        chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)last_reg_, gidx));
    } else {
        // Load current global value
        int cur = allocReg();
        chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)cur, gidx));
        // Compile rhs
        s.value->accept(*this);
        int rhs = last_reg_;
        int res = allocReg();
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        chunk.emit(makeABC((uint8_t)charToOp(s.op), (uint8_t)res, (uint8_t)cur, (uint8_t)rhs));
        chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)res, gidx));
    }
    reg_top_ = saved;
}

void Compiler::visit(const ExprStmt& s) {
    int saved = reg_top_;
    s.expr->accept(*this);
    reg_top_ = saved;
}

void Compiler::visit(const ThrowStmt& s) {
    int saved = reg_top_;
    s.value->accept(*this);
    int r = last_reg_;
    chunk.emit(makeABC((uint8_t)Op::THROW, (uint8_t)r, 0, 0));
    reg_top_ = saved;
}

void Compiler::visit(const TryCatchStmt& s) {
    int catch_r = s.catch_var.empty() ? 0 : local_regs_.at(s.catch_var);

    size_t try_patch = chunk.emitJump(Op::TRY, (uint8_t)catch_r);

    for (auto& stmt : s.try_body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }

    chunk.emit(makeBx((uint8_t)Op::POP_TRY, 0));
    size_t else_patch = chunk.emitJump(Op::JUMP);

    uint16_t catch_addr = (uint16_t)chunk.currentPos();
    chunk.patchJump(try_patch, catch_addr);

    for (auto& stmt : s.catch_body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }
    size_t end_patch = chunk.emitJump(Op::JUMP);

    uint16_t else_addr = (uint16_t)chunk.currentPos();
    chunk.patchJump(else_patch, else_addr);

    for (auto& stmt : s.else_body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }

    uint16_t end_addr = (uint16_t)chunk.currentPos();
    chunk.patchJump(end_patch, end_addr);
}

void Compiler::visit(const FuncDeclStmt& s) {
    // Save outer context
    auto outer_regs    = std::move(local_regs_);
    auto outer_upvals  = std::move(cur_upval_idx_);
    int  outer_top     = reg_top_;
    int  outer_count   = reg_count_;
    int  outer_locals  = locals_top_;
    auto outer_name    = current_func_name;
    int  outer_fidx    = current_func_idx_;
    bool is_nested     = !outer_name.empty();  // déclarée dans une autre fonction

    // Push outer scope for upvalue resolution
    outer_scopes_.push_back({outer_regs, outer_upvals, outer_fidx});

    current_func_name = s.name;
    cur_upval_idx_.clear();
    local_regs_.clear();
    reg_top_ = 0;
    reg_count_ = 0;
    locals_top_ = 0;

    // Assign parameter registers
    int n_fixed = (int)s.params.size();
    for (int i = 0; i < n_fixed; ++i)
        local_regs_[s.params[i]] = i;
    reg_top_ = n_fixed;

    // Pre-scan body for all var declarations and for-loop variables
    std::vector<std::string> body_locals;
    collectLocals(s.body, body_locals);
    for (auto& name : body_locals) {
        if (!local_regs_.count(name))
            local_regs_[name] = reg_top_++;
    }
    locals_top_ = reg_top_;
    reg_count_  = reg_top_;

    // Emit jump over function body
    size_t jump_patch = chunk.emitJump(Op::JUMP);
    uint32_t func_addr = (uint32_t)chunk.currentPos();

    // Build default values
    std::vector<Value> defs(n_fixed);
    for (int i = 0; i < n_fixed; ++i)
        defs[i] = (i < (int)s.defaults.size() && s.defaults[i])
                  ? evalConstant(*s.defaults[i]) : Value{};
    uint16_t defaults_idx = chunk.addFuncDefaults(std::move(defs));

    FuncProto fp{func_addr, (uint8_t)n_fixed, s.variadic, defaults_idx, 0, {}};
    uint8_t func_idx = chunk.addFunc(fp);
    current_func_idx_ = func_idx;

    bool outer_has_vars = !outer_scopes_.back().regs.empty();

    if (!is_nested) {
        // Fonction top-level : pré-marque dans func_table pour optimiser les appels
        // récursifs (CALL_DYN au lieu de CALL_FUNC quand la fonction peut être closure)
        func_table[s.name] = FuncInfo{func_idx, n_fixed, s.variadic, outer_has_vars};
    }
    // Fonctions imbriquées : pas de func_table — elles vivent dans un registre local

    // Compile body
    for (auto& stmt : s.body) {
        int saved = reg_top_;
        stmt->accept(*this);
        reg_top_ = saved;
    }
    chunk.emit(makeABC((uint8_t)Op::RETURN, 0, 0, 0));  // implicit void return

    // Update reg_count in FuncProto
    chunk.funcs[func_idx].reg_count = (uint8_t)reg_count_;

    // Patch jump over body
    chunk.patchJump(jump_patch, (uint16_t)chunk.currentPos());

    // Pop scope and restore outer context
    outer_scopes_.pop_back();
    local_regs_        = std::move(outer_regs);
    cur_upval_idx_     = std::move(outer_upvals);
    reg_top_           = outer_top;
    reg_count_         = outer_count;
    locals_top_        = outer_locals;
    current_func_name  = outer_name;
    current_func_idx_  = outer_fidx;

    bool has_upvals = !chunk.funcs[func_idx].upvals.empty();

    if (is_nested) {
        // Fonction imbriquée : stockée dans le registre local pré-alloué par collectLocals.
        // Aucune entrée dans func_table, aucun accès aux globaux.
        int dest = local_regs_.at(s.name);
        if (has_upvals) {
            chunk.emit(makeABx((uint8_t)Op::MAKE_CLOSURE, (uint8_t)dest, func_idx));
        } else {
            chunk.emit(makeABx((uint8_t)Op::LOAD_FUNC, (uint8_t)dest, func_idx));
        }
    } else if (has_upvals) {
        // Fonction top-level closure : MAKE_CLOSURE + STORE_GLOBAL
        func_table[s.name].is_closure = true;
        int tmp = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        chunk.emit(makeABx((uint8_t)Op::MAKE_CLOSURE, (uint8_t)tmp, func_idx));
        chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)tmp,
                           chunk.addIdentifier(s.name)));
        reg_top_--;
    } else if (outer_has_vars) {
        // Fonction top-level non-closure dans un scope avec vars : LOAD_FUNC + STORE_GLOBAL
        // pour que les appels récursifs via LOAD_GLOBAL (pré-marquage) trouvent la valeur.
        func_table[s.name].is_closure = false;
        int tmp = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        chunk.emit(makeABx((uint8_t)Op::LOAD_FUNC, (uint8_t)tmp, func_idx));
        chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)tmp,
                           chunk.addIdentifier(s.name)));
        reg_top_--;
    }
}

void Compiler::visit(const ReturnStmt& s) {
    if (!inFunction())
        throw std::runtime_error("return outside function");
    if (s.spread_varargs) {
        int base = reg_top_;
        for (int i = 0; i < (int)s.values.size(); ++i) {
            int target = base + i;
            reg_top_ = target;
            s.values[i]->accept(*this);
            if (last_reg_ != target)
                chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)target, (uint8_t)last_reg_, 0));
            reg_top_ = target + 1;
            if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        }
        chunk.emit(makeABC((uint8_t)Op::RETURN_V, (uint8_t)base,
                           (uint8_t)s.values.size(), 0));
    } else {
        int n = (int)s.values.size();
        if (n == 0) {
            chunk.emit(makeABC((uint8_t)Op::RETURN, 0, 0, 0));
        } else {
            int base = reg_top_;
            for (int i = 0; i < n; ++i) {
                int target = base + i;
                reg_top_ = target;
                s.values[i]->accept(*this);
                if (last_reg_ != target)
                    chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)target,
                                       (uint8_t)last_reg_, 0));
                reg_top_ = target + 1;
                if (reg_top_ > reg_count_) reg_count_ = reg_top_;
            }
            chunk.emit(makeABC((uint8_t)Op::RETURN, (uint8_t)base, (uint8_t)n, 0));
        }
    }
}

void Compiler::visit(const ForStmt& s) {
    int base_reg = reg_top_;

    int i_reg;
    if (local_regs_.count(s.var)) {
        i_reg = local_regs_.at(s.var);   // pré-alloué par collectLocals
    } else {
        i_reg = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
    }
    compileInto(*s.start, i_reg);

    int end_reg = reg_top_++;
    if (reg_top_ > reg_count_) reg_count_ = reg_top_;
    compileInto(*s.end, end_reg);

    int step_reg = -1;
    if (s.step) {
        step_reg = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        compileInto(*s.step, step_reg);
    }

    int one_r = -1;
    if (step_reg < 0) {
        one_r = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)one_r,
                           chunk.addConstant(Value((int64_t)1))));
    }

    auto loop_start = (uint16_t)chunk.currentPos();

    int sc0 = reg_top_, sc1 = reg_top_ + 1, cond_r = reg_top_ + 2;
    if (reg_top_ + 3 > reg_count_) reg_count_ = reg_top_ + 3;

    size_t exit_patch;
    if (step_reg < 0) {
        chunk.emit(makeABC((uint8_t)Op::LE, (uint8_t)cond_r, (uint8_t)i_reg, (uint8_t)end_reg));
        exit_patch = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);
    } else {
        chunk.emit(makeABC((uint8_t)Op::SUB, (uint8_t)sc0, (uint8_t)end_reg, (uint8_t)i_reg));
        chunk.emit(makeABC((uint8_t)Op::MUL, (uint8_t)sc0, (uint8_t)sc0, (uint8_t)step_reg));
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)sc1,
                           chunk.addConstant(Value((int64_t)0))));
        chunk.emit(makeABC((uint8_t)Op::GE, (uint8_t)cond_r, (uint8_t)sc0, (uint8_t)sc1));
        exit_patch = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);
    }

    break_patches.push_back({});
    continue_patches.push_back({});
    for (auto& stmt : s.body) {
        int saved = reg_top_;
        stmt->accept(*this);
        reg_top_ = saved;
    }

    uint16_t incr_addr = (uint16_t)chunk.currentPos();
    for (size_t p : continue_patches.back()) chunk.patchJump(p, incr_addr);
    continue_patches.pop_back();

    if (step_reg < 0)
        chunk.emit(makeABC((uint8_t)Op::ADD, (uint8_t)i_reg, (uint8_t)i_reg, (uint8_t)one_r));
    else
        chunk.emit(makeABC((uint8_t)Op::ADD, (uint8_t)i_reg, (uint8_t)i_reg, (uint8_t)step_reg));

    chunk.emit(makeBx((uint8_t)Op::JUMP, loop_start));

    uint16_t exit = (uint16_t)chunk.currentPos();
    chunk.patchJump(exit_patch, exit);
    for (size_t p : break_patches.back()) chunk.patchJump(p, exit);
    break_patches.pop_back();

    reg_top_ = base_reg;  // libère end/step/one_r ; i est pré-alloué, reste intact
}

// ── expressions ───────────────────────────────────────────────────────────────

void Compiler::visit(const NumberExpr& e) {
    last_reg_ = allocReg();
    chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_,
                       chunk.addConstant(numValue(e.value))));
}

void Compiler::visit(const StringExpr& e) {
    last_reg_ = allocReg();
    chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_,
                       chunk.addConstant(Value(e.value))));
}

void Compiler::visit(const BoolExpr& e) {
    last_reg_ = allocReg();
    chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_,
                       chunk.addConstant(Value((int64_t)(e.value ? 1 : 0)))));
}

void Compiler::visit(const NilExpr&) {
    last_reg_ = allocReg();
    chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)last_reg_, 0, 0));
}

void Compiler::visit(const VarExpr& e) {
    // Local variable shadows everything (including global functions of the same name)
    {
        auto it = local_regs_.find(e.name);
        if (it != local_regs_.end()) {
            last_reg_ = it->second;
            return;
        }
    }
    // Référence à une fonction globale
    auto fit = func_table.find(e.name);
    if (fit != func_table.end()) {
        last_reg_ = allocReg();
        if (fit->second.is_closure) {
            chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)last_reg_,
                               chunk.addIdentifier(e.name)));
        } else {
            chunk.emit(makeABx((uint8_t)Op::LOAD_FUNC, (uint8_t)last_reg_,
                               fit->second.func_idx));
        }
        return;
    }
    // Upvalue
    {
        int uv = resolveUpvalue(e.name);
        if (uv >= 0) {
            last_reg_ = allocReg();
            chunk.emit(makeABC((uint8_t)Op::GET_UPVAL, (uint8_t)last_reg_, (uint8_t)uv, 0));
            return;
        }
    }
    // Global
    last_reg_ = allocReg();
    chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)last_reg_,
                       chunk.addIdentifier(e.name)));
}

void Compiler::visit(const BinaryExpr& e) {
    e.left->accept(*this);  int rL = last_reg_;
    int saved_after_left = reg_top_;
    e.right->accept(*this); int rR = last_reg_;
    last_reg_ = reg_top_++;
    if (reg_top_ > reg_count_) reg_count_ = reg_top_;

    switch (e.op) {
        case '+': chunk.emit(makeABC((uint8_t)Op::ADD, (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case '-': chunk.emit(makeABC((uint8_t)Op::SUB, (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case '*': chunk.emit(makeABC((uint8_t)Op::MUL, (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case '/': chunk.emit(makeABC((uint8_t)Op::DIV, (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case '%': chunk.emit(makeABC((uint8_t)Op::MOD, (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case '>': chunk.emit(makeABC((uint8_t)Op::GT,  (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case '<': chunk.emit(makeABC((uint8_t)Op::LT,  (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case 'G': chunk.emit(makeABC((uint8_t)Op::GE,  (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case 'L': chunk.emit(makeABC((uint8_t)Op::LE,  (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case 'N': chunk.emit(makeABC((uint8_t)Op::NEQ, (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case '=': chunk.emit(makeABC((uint8_t)Op::EQ,  (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case '|': chunk.emit(makeABC((uint8_t)Op::OR,      (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case '&': chunk.emit(makeABC((uint8_t)Op::AND,     (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case 'o': chunk.emit(makeABC((uint8_t)Op::BOR,     (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case 'b': chunk.emit(makeABC((uint8_t)Op::BAND,    (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case 'x': chunk.emit(makeABC((uint8_t)Op::BXOR,   (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case 'l': chunk.emit(makeABC((uint8_t)Op::BLSHIFT, (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case 'r': chunk.emit(makeABC((uint8_t)Op::BRSHIFT, (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        default:  throw std::runtime_error(std::string("unknown binary op: ") + e.op);
    }
    (void)saved_after_left;
}

void Compiler::visit(const UnaryExpr& e) {
    e.operand->accept(*this);
    int rIn = last_reg_;
    last_reg_ = allocReg();
    if (e.op == '-')
        chunk.emit(makeABC((uint8_t)Op::NEGATE, (uint8_t)last_reg_, (uint8_t)rIn, 0));
    else if (e.op == '!')
        chunk.emit(makeABC((uint8_t)Op::NOT, (uint8_t)last_reg_, (uint8_t)rIn, 0));
    else if (e.op == '~')
        chunk.emit(makeABC((uint8_t)Op::BNOT, (uint8_t)last_reg_, (uint8_t)rIn, 0));
    else
        throw std::runtime_error(std::string("unknown unary op: ") + e.op);
}

void Compiler::visit(const CallExpr& e) {
    // Check if it's a user-defined function
    auto it = func_table.find(e.callee);
    if (it != func_table.end()) {
        int call_base = reg_top_;
        int argc = (int)e.args.size();
        for (int i = 0; i < argc; ++i) {
            int target = call_base + i;
            reg_top_ = target;
            e.args[i]->accept(*this);
            if (last_reg_ != target)
                chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)target,
                                   (uint8_t)last_reg_, 0));
            reg_top_ = target + 1;
            if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        }
        if (it->second.is_closure) {
            int func_reg = reg_top_++;
            if (reg_top_ > reg_count_) reg_count_ = reg_top_;
            chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)func_reg,
                               chunk.addIdentifier(e.callee)));
            chunk.emit(makeABC((uint8_t)Op::CALL_DYN, (uint8_t)call_base,
                               (uint8_t)func_reg, (uint8_t)argc));
        } else {
            chunk.emit(makeABC((uint8_t)Op::CALL_FUNC, (uint8_t)call_base,
                               it->second.func_idx, (uint8_t)argc));
        }
        last_reg_ = call_base;
        return;
    }

    // Builtins
    int call_base = reg_top_;
    int argc = (int)e.args.size();
    for (int i = 0; i < argc; ++i) {
        int target = call_base + i;
        reg_top_ = target;
        e.args[i]->accept(*this);
        if (last_reg_ != target)
            chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)target,
                               (uint8_t)last_reg_, 0));
        reg_top_ = target + 1;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
    }

    // Tous les appels passent par CALL_DYN — builtins sont des globaux T_BUILTIN
    {
        int func_reg = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        {
            auto rit = local_regs_.find(e.callee);
            if (rit != local_regs_.end()) {
                func_reg = rit->second;
                reg_top_--;
            } else {
                int uv = resolveUpvalue(e.callee);
                if (uv >= 0) {
                    chunk.emit(makeABC((uint8_t)Op::GET_UPVAL, (uint8_t)func_reg, (uint8_t)uv, 0));
                } else {
                    chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)func_reg,
                                       chunk.addIdentifier(e.callee)));
                }
            }
        }
        chunk.emit(makeABC((uint8_t)Op::CALL_DYN, (uint8_t)call_base,
                           (uint8_t)func_reg, (uint8_t)argc));
        last_reg_ = call_base;
    }
}

void Compiler::visit(const ExprCallExpr& e) {
    int call_base = reg_top_;
    int argc = (int)e.args.size();

    // Compile args into consecutive registers
    for (int i = 0; i < argc; ++i) {
        int target = call_base + i;
        reg_top_ = target;
        e.args[i]->accept(*this);
        if (last_reg_ != target)
            chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)target, (uint8_t)last_reg_, 0));
        reg_top_ = target + 1;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
    }

    // Compile callee into a temp register after args
    int func_reg = reg_top_++;
    if (reg_top_ > reg_count_) reg_count_ = reg_top_;
    compileInto(*e.callee, func_reg);

    chunk.emit(makeABC((uint8_t)Op::CALL_DYN, (uint8_t)call_base,
                       (uint8_t)func_reg, (uint8_t)argc));
    last_reg_ = call_base;
}

void Compiler::visit(const VarArgExpr&) {
    if (!inFunction())
        throw std::runtime_error("... outside a variadic function");
    int base = reg_top_;
    chunk.emit(makeABC((uint8_t)Op::LOAD_VARARGS, (uint8_t)base, 0, 0));
    last_reg_ = base;
}

void Compiler::visit(const MapExpr& e) {
    int dest = allocReg();
    chunk.emit(makeABC((uint8_t)Op::NEW_MAP, (uint8_t)dest, 0, 0));
    for (auto& entry : e.entries) {
        int saved = reg_top_;
        int key_reg = allocReg();
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_reg,
                           chunk.addConstant(Value(entry.first))));
        int val_reg = allocReg();
        compileInto(*entry.second, val_reg);
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_reg, (uint8_t)val_reg));
        reg_top_ = saved;
    }
    last_reg_ = dest;
}

void Compiler::visit(const IndexExpr& e) {
    int saved = reg_top_;
    e.obj->accept(*this);
    int obj_r = last_reg_;
    int saved2 = reg_top_;
    e.key->accept(*this);
    int key_r = last_reg_;
    reg_top_ = saved2;
    int dest = allocReg();
    chunk.emit(makeABC((uint8_t)Op::GET_INDEX, (uint8_t)dest, (uint8_t)obj_r, (uint8_t)key_r));
    last_reg_ = dest;
    (void)saved;
}

void Compiler::visit(const ArrayExpr& e) {
    int dest = allocReg();
    chunk.emit(makeABC((uint8_t)Op::NEW_ARRAY, (uint8_t)dest, 0, 0));
    for (auto& elem : e.elements) {
        int saved = reg_top_;
        int val_r = allocReg();
        compileInto(*elem, val_r);
        chunk.emit(makeABC((uint8_t)Op::ARRAY_PUSH, (uint8_t)dest, (uint8_t)val_r, 0));
        reg_top_ = saved;
    }
    last_reg_ = dest;
}

void Compiler::compileIteratorLoop(const Expr& src,
                                   const std::string& key_var,
                                   const std::string& val_var,
                                   const std::vector<std::unique_ptr<Stmt>>& body) {
    auto bind = [&](const std::string& name, int src_reg) {
        auto it = local_regs_.find(name);
        if (it != local_regs_.end()) {
            if (it->second != src_reg)
                chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)it->second, (uint8_t)src_reg, 0));
        } else {
            chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL,
                               (uint8_t)src_reg, chunk.addIdentifier(name)));
        }
    };

    int block = reg_top_;
    reg_top_ += 4;
    if (reg_top_ > reg_count_) reg_count_ = reg_top_;

    compileInto(src, block + 3);
    chunk.emit(makeABC((uint8_t)Op::MAKE_ITER, (uint8_t)(block), (uint8_t)(block + 3), 0));
    reg_top_ = block + 3;

    auto loop_start = (uint16_t)chunk.currentPos();
    size_t exit_patch = chunk.emitJump(Op::FOR_ITER_NEXT, (uint8_t)block);

    if (!key_var.empty()) bind(key_var, block + 1);
    bind(val_var, block + 2);

    break_patches.push_back({});
    continue_patches.push_back({});
    for (auto& stmt : body) {
        int saved = reg_top_;
        stmt->accept(*this);
        reg_top_ = saved;
    }
    for (size_t p : continue_patches.back()) chunk.patchJump(p, loop_start);
    continue_patches.pop_back();
    chunk.emit(makeBx((uint8_t)Op::JUMP, loop_start));

    uint16_t exit = (uint16_t)chunk.currentPos();
    chunk.patchJump(exit_patch, exit);
    for (size_t p : break_patches.back()) chunk.patchJump(p, exit);
    break_patches.pop_back();

    reg_top_ = block;
}

void Compiler::visit(const ForMapStmt& s) {
    compileIteratorLoop(*s.map_expr, s.key_var, s.val_var, s.body);
}

void Compiler::visit(const ForInStmt& s) {
    compileIteratorLoop(*s.iter_expr, "", s.val_var, s.body);
}

void Compiler::visit(const IndexAssignStmt& s) {
    int saved = reg_top_;

    // Load the map object
    int obj_r;
    {
        auto it = local_regs_.find(s.obj);
        if (it != local_regs_.end()) {
            obj_r = it->second;
        } else {
            obj_r = allocReg();
            chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)obj_r,
                               chunk.addIdentifier(s.obj)));
        }
    }

    // Compile key
    int key_r = allocReg();
    compileInto(*s.key, key_r);

    if (s.op == TokenType::EQUALS) {
        // Simple assignment: SET_INDEX obj_r, key_r, val_r
        int val_r = allocReg();
        compileInto(*s.value, val_r);
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)obj_r, (uint8_t)key_r, (uint8_t)val_r));
    } else {
        // Compound assignment: get current, apply op, store back
        int cur_r = allocReg();
        chunk.emit(makeABC((uint8_t)Op::GET_INDEX, (uint8_t)cur_r, (uint8_t)obj_r, (uint8_t)key_r));
        int rhs_r = allocReg();
        compileInto(*s.value, rhs_r);
        int result_r = allocReg();
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        chunk.emit(makeABC((uint8_t)tokenToOp(s.op), (uint8_t)result_r, (uint8_t)cur_r, (uint8_t)rhs_r));
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)obj_r, (uint8_t)key_r, (uint8_t)result_r));
    }
    reg_top_ = saved;
}

void Compiler::visit(const BlockStmt& s) {
    for (auto& stmt : s.stmts) stmt->accept(*this);
}

// ── compileMethodFunc : compile une méthode avec 'self' implicite en R[0] ──────
uint8_t Compiler::compileMethodFunc(const FuncDeclStmt& s) {
    auto outer_regs   = std::move(local_regs_);
    auto outer_upvals = std::move(cur_upval_idx_);
    int  outer_top    = reg_top_;
    int  outer_count  = reg_count_;
    int  outer_locals = locals_top_;
    auto outer_name   = current_func_name;
    int  outer_fidx   = current_func_idx_;

    outer_scopes_.push_back({outer_regs, outer_upvals, outer_fidx});

    current_func_name = s.name;
    cur_upval_idx_.clear();
    local_regs_.clear();
    reg_top_ = 0;
    reg_count_ = 0;
    locals_top_ = 0;

    // 'self' en R[0], puis les paramètres déclarés en R[1..n]
    local_regs_["self"] = 0;
    int n_params = (int)s.params.size();
    for (int i = 0; i < n_params; ++i)
        local_regs_[s.params[i]] = i + 1;
    int n_fixed = 1 + n_params;
    reg_top_ = n_fixed;

    std::vector<std::string> body_locals;
    collectLocals(s.body, body_locals);
    for (auto& name : body_locals)
        if (!local_regs_.count(name))
            local_regs_[name] = reg_top_++;
    locals_top_ = reg_top_;
    reg_count_  = reg_top_;

    size_t jump_patch = chunk.emitJump(Op::JUMP);
    uint32_t func_addr = (uint32_t)chunk.currentPos();

    // defaults : index 0 = self (pas de défaut), puis les params
    std::vector<Value> defs(n_fixed);
    for (int i = 0; i < n_params; ++i)
        defs[i+1] = (i < (int)s.defaults.size() && s.defaults[i])
                    ? evalConstant(*s.defaults[i]) : Value{};
    uint16_t defaults_idx = chunk.addFuncDefaults(std::move(defs));

    FuncProto fp{func_addr, (uint8_t)n_fixed, s.variadic, defaults_idx, 0, {}};
    uint8_t func_idx = chunk.addFunc(fp);
    current_func_idx_ = func_idx;

    for (auto& stmt : s.body) {
        int sv = reg_top_;
        stmt->accept(*this);
        reg_top_ = sv;
    }
    chunk.emit(makeABC((uint8_t)Op::RETURN, 0, 0, 0));

    chunk.funcs[func_idx].reg_count = (uint8_t)reg_count_;
    chunk.patchJump(jump_patch, (uint16_t)chunk.currentPos());

    outer_scopes_.pop_back();
    local_regs_       = std::move(outer_regs);
    cur_upval_idx_    = std::move(outer_upvals);
    reg_top_          = outer_top;
    reg_count_        = outer_count;
    locals_top_       = outer_locals;
    current_func_name = outer_name;
    current_func_idx_ = outer_fidx;

    return func_idx;
}

// ── visit(ClassDeclStmt) ──────────────────────────────────────────────────────
void Compiler::visit(const ClassDeclStmt& s) {
    int saved = reg_top_;

    // Créer la valeur classe (T_CLASS = map vide)
    int dest = reg_top_++;
    if (reg_top_ > reg_count_) reg_count_ = reg_top_;
    chunk.emit(makeABC((uint8_t)Op::NEW_CLASS, (uint8_t)dest, 0, 0));

    // Stocker le nom de la classe comme __name__ (utile pour print/debug)
    {
        int key_r = reg_top_++, val_r = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r,
                           chunk.addConstant(Value(std::string("__name__")))));
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)val_r,
                           chunk.addConstant(Value(s.name))));
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_r, (uint8_t)val_r));
        reg_top_ = dest + 1;
    }

    // Héritage : stocker la classe parente comme __parent__
    if (!s.parent.empty()) {
        int par_r = reg_top_++, key_r = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)par_r,
                           chunk.addIdentifier(s.parent)));
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r,
                           chunk.addConstant(Value(std::string("__parent__")))));
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_r, (uint8_t)par_r));
        reg_top_ = dest + 1;
    }

    // Compiler chaque méthode et la stocker dans la map classe
    for (auto& method : s.methods) {
        uint8_t func_idx = compileMethodFunc(*method);
        bool has_upvals = !chunk.funcs[func_idx].upvals.empty();

        int func_r = reg_top_++, key_r = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        if (has_upvals)
            chunk.emit(makeABx((uint8_t)Op::MAKE_CLOSURE, (uint8_t)func_r, func_idx));
        else
            chunk.emit(makeABx((uint8_t)Op::LOAD_FUNC, (uint8_t)func_r, func_idx));
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r,
                           chunk.addConstant(Value(method->name))));
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_r, (uint8_t)func_r));
        reg_top_ = dest + 1;
    }

    // Stocker la classe comme global
    chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)dest,
                       chunk.addIdentifier(s.name)));

    reg_top_ = saved;
}

// ── visit(MethodCallExpr) ─────────────────────────────────────────────────────
// Layout : R[call_base+0]=self, R[call_base+1]=méthode, R[call_base+2..]=args
// CALL_METHOD décale les args de 1 vers le bas (overwrite méthode) avant l'appel.
void Compiler::visit(const MethodCallExpr& e) {
    int call_base = reg_top_;
    int argc = (int)e.args.size();

    if (e.is_super) {
        // self est en local_regs_["self"] — copier en call_base
        int self_src = local_regs_.at("self");
        reg_top_ = call_base + 1;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)call_base, (uint8_t)self_src, 0));

        // Temporaires pour remonter la chaîne : tmp=class_chain, key_r=clé
        int tmp = reg_top_++, key_r = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;

        // tmp = self.__class__
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r,
                           chunk.addConstant(Value(std::string("__class__")))));
        chunk.emit(makeABC((uint8_t)Op::GET_INDEX, (uint8_t)tmp, (uint8_t)call_base, (uint8_t)key_r));
        // tmp = tmp.__parent__
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r,
                           chunk.addConstant(Value(std::string("__parent__")))));
        chunk.emit(makeABC((uint8_t)Op::GET_INDEX, (uint8_t)tmp, (uint8_t)tmp, (uint8_t)key_r));
        // R[call_base+1] = tmp.<method>
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r,
                           chunk.addConstant(Value(std::string(e.method)))));
        chunk.emit(makeABC((uint8_t)Op::GET_INDEX, (uint8_t)(call_base+1), (uint8_t)tmp, (uint8_t)key_r));
        reg_top_ = call_base + 2;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
    } else {
        // R[call_base] = receiver (self)
        compileInto(*e.receiver, call_base);
        reg_top_ = call_base + 1;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;

        // R[call_base+1] = GET_INDEX(receiver, method_name)
        int key_r = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r,
                           chunk.addConstant(Value(std::string(e.method)))));
        chunk.emit(makeABC((uint8_t)Op::GET_INDEX, (uint8_t)(call_base+1), (uint8_t)call_base, (uint8_t)key_r));
        reg_top_ = call_base + 2;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
    }

    // R[call_base+2..argc+1] = args
    for (int i = 0; i < argc; ++i) {
        int target = call_base + 2 + i;
        reg_top_ = target;
        e.args[i]->accept(*this);
        if (last_reg_ != target)
            chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)target, (uint8_t)last_reg_, 0));
        reg_top_ = target + 1;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
    }

    chunk.emit(makeABC((uint8_t)Op::CALL_METHOD, (uint8_t)call_base, 0, (uint8_t)argc));
    last_reg_ = call_base;
}
