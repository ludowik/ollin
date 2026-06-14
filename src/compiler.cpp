#include "compiler.h"
#include <algorithm>
#include <stdexcept>

// ── constant evaluator (for default parameter values) ─────────────────────────
static Value evalConstant(const Expr& e) {
    if (auto* n = dynamic_cast<const NumberExpr*>(&e)) return Value(n->value);
    if (auto* s = dynamic_cast<const StringExpr*>(&e)) return Value(s->value);
    if (auto* b = dynamic_cast<const BoolExpr*>(&e))   return Value(b->value ? 1.0 : 0.0);
    if (dynamic_cast<const NilExpr*>(&e))               return Value{};
    throw std::runtime_error("default values must be literal constants");
}

// ── pre-scan locals in a block (for register pre-allocation) ─────────────────
static void collectLocals(const std::vector<std::unique_ptr<Stmt>>& stmts,
                          std::vector<std::string>& out) {
    for (auto& s : stmts) {
        if (auto* v = dynamic_cast<const VarDeclStmt*>(s.get()))
            for (auto& n : v->names)
                if (std::find(out.begin(), out.end(), n) == out.end())
                    out.push_back(n);
        if (auto* f = dynamic_cast<const ForStmt*>(s.get())) {
            if (std::find(out.begin(), out.end(), f->var) == out.end())
                out.push_back(f->var);
            collectLocals(f->body, out);
        }
        if (auto* w = dynamic_cast<const WhileStmt*>(s.get()))
            collectLocals(w->body, out);
        if (auto* i = dynamic_cast<const IfStmt*>(s.get())) {
            collectLocals(i->then_body, out);
            for (auto& ei : i->else_ifs) collectLocals(ei.body, out);
            collectLocals(i->else_body, out);
        }
        if (auto* t = dynamic_cast<const TryCatchStmt*>(s.get())) {
            collectLocals(t->try_body, out);
            if (!t->catch_var.empty() &&
                std::find(out.begin(), out.end(), t->catch_var) == out.end())
                out.push_back(t->catch_var);
            collectLocals(t->catch_body, out);
            collectLocals(t->else_body, out);
        }
    }
}

// ── compile expression into a specific destination register ──────────────────
void Compiler::compileInto(const Expr& e, int dest) {
    if (auto* n = dynamic_cast<const NumberExpr*>(&e)) {
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)dest,
                           chunk.addConstant(Value(n->value))));
    } else if (auto* s = dynamic_cast<const StringExpr*>(&e)) {
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)dest,
                           chunk.addConstant(Value(s->value))));
    } else if (auto* b = dynamic_cast<const BoolExpr*>(&e)) {
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)dest,
                           chunk.addConstant(Value(b->value ? 1.0 : 0.0))));
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
    // Pre-scan top-level locals to assign stable global registers
    // (We don't do this at top-level since they're globals, not locals)
    reg_top_ = 0;
    reg_count_ = 8;  // minimum
    for (auto& s : prog.stmts)
        s->accept(*this);
    chunk.top_reg_count = (uint8_t)std::max(reg_count_, 8);
    chunk.emit(makeBx((uint8_t)Op::HALT, 0));
    return std::move(chunk);
}

// ── statements ────────────────────────────────────────────────────────────────

void Compiler::visit(const VarDeclStmt& s) {
    if (inFunction()) {
        // Multi-return from user function call
        if (s.names.size() > 1 && s.values.size() == 1) {
            if (auto* call = dynamic_cast<const CallExpr*>(s.values[0].get())) {
                if (func_table.count(call->callee)) {
                    // Compile the call, results start at call_base
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
                                       (uint8_t)call_base,
                                       fi.func_idx,
                                       (uint8_t)argc));
                    // Move results to their pre-allocated local registers
                    for (int i = 0; i < (int)s.names.size(); ++i) {
                        int dest = local_regs_.at(s.names[i]);
                        if (call_base + i != dest)
                            chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)dest,
                                               (uint8_t)(call_base + i), 0));
                    }
                    reg_top_ = call_base;  // free temps
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
    } else {
        // Global scope: multi-return from user function
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
                                       (uint8_t)call_base,
                                       fi.func_idx,
                                       (uint8_t)argc));
                    for (int i = 0; i < (int)s.names.size(); ++i) {
                        uint16_t gidx = chunk.addIdentifier(s.names[i]);
                        chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL,
                                           (uint8_t)(call_base + i), gidx));
                    }
                    reg_top_ = call_base;
                    return;
                }
            }
        }
        // Normal global declarations
        for (int i = 0; i < (int)s.names.size(); ++i) {
            int saved = reg_top_;
            uint16_t gidx = chunk.addIdentifier(s.names[i]);
            if (i < (int)s.values.size()) {
                s.values[i]->accept(*this);
            } else {
                last_reg_ = allocReg();
                chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)last_reg_, 0, 0));
            }
            chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)last_reg_, gidx));
            reg_top_ = saved;
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
    for (auto& stmt : s.body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }
    chunk.emit(makeBx((uint8_t)Op::JUMP, loop_start));
    chunk.patchJump(exit_patch, (uint16_t)chunk.currentPos());
    for (size_t p : break_patches.back())
        chunk.patchJump(p, (uint16_t)chunk.currentPos());
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

void Compiler::visit(const AssignStmt& s) {
    if (inFunction()) {
        auto it = local_regs_.find(s.name);
        if (it != local_regs_.end()) {
            int dest = it->second;
            if (s.op == '\0') {
                compileInto(*s.value, dest);
            } else {
                // Compound: load current value, compile rhs, apply op
                int saved = reg_top_;
                // rhs in a temp
                s.value->accept(*this);
                int rhs = last_reg_;
                // result reg
                int res = allocReg();
                if (reg_top_ > reg_count_) reg_count_ = reg_top_;
                switch (s.op) {
                    case '+': chunk.emit(makeABC((uint8_t)Op::ADD, (uint8_t)res, (uint8_t)dest, (uint8_t)rhs)); break;
                    case '-': chunk.emit(makeABC((uint8_t)Op::SUB, (uint8_t)res, (uint8_t)dest, (uint8_t)rhs)); break;
                    case '*': chunk.emit(makeABC((uint8_t)Op::MUL, (uint8_t)res, (uint8_t)dest, (uint8_t)rhs)); break;
                    case '/': chunk.emit(makeABC((uint8_t)Op::DIV, (uint8_t)res, (uint8_t)dest, (uint8_t)rhs)); break;
                    case '%': chunk.emit(makeABC((uint8_t)Op::MOD, (uint8_t)res, (uint8_t)dest, (uint8_t)rhs)); break;
                    default:  throw std::runtime_error(std::string("unknown assign op: ") + s.op);
                }
                chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)dest, (uint8_t)res, 0));
                reg_top_ = saved;
            }
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
        switch (s.op) {
            case '+': chunk.emit(makeABC((uint8_t)Op::ADD, (uint8_t)res, (uint8_t)cur, (uint8_t)rhs)); break;
            case '-': chunk.emit(makeABC((uint8_t)Op::SUB, (uint8_t)res, (uint8_t)cur, (uint8_t)rhs)); break;
            case '*': chunk.emit(makeABC((uint8_t)Op::MUL, (uint8_t)res, (uint8_t)cur, (uint8_t)rhs)); break;
            case '/': chunk.emit(makeABC((uint8_t)Op::DIV, (uint8_t)res, (uint8_t)cur, (uint8_t)rhs)); break;
            case '%': chunk.emit(makeABC((uint8_t)Op::MOD, (uint8_t)res, (uint8_t)cur, (uint8_t)rhs)); break;
            default:  throw std::runtime_error(std::string("unknown assign op: ") + s.op);
        }
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
    if (inFunction()) {
        // catch_var is a local register (pre-allocated by collectLocals)
        int catch_r = s.catch_var.empty() ? 0 : local_regs_.at(s.catch_var);

        // TRY: A=catch_reg, Bx=catch_addr (patched later)
        size_t try_patch = chunk.emitJump(Op::TRY, (uint8_t)catch_r);

        for (auto& stmt : s.try_body) {
            int s2 = reg_top_;
            stmt->accept(*this);
            reg_top_ = s2;
        }

        chunk.emit(makeBx((uint8_t)Op::POP_TRY, 0));
        size_t else_patch = chunk.emitJump(Op::JUMP);

        // catch block
        uint16_t catch_addr = (uint16_t)chunk.currentPos();
        chunk.patchJump(try_patch, catch_addr);

        for (auto& stmt : s.catch_body) {
            int s2 = reg_top_;
            stmt->accept(*this);
            reg_top_ = s2;
        }
        size_t end_patch = chunk.emitJump(Op::JUMP);

        // else block
        uint16_t else_addr = (uint16_t)chunk.currentPos();
        chunk.patchJump(else_patch, else_addr);

        for (auto& stmt : s.else_body) {
            int s2 = reg_top_;
            stmt->accept(*this);
            reg_top_ = s2;
        }

        uint16_t end_addr = (uint16_t)chunk.currentPos();
        chunk.patchJump(end_patch, end_addr);
    } else {
        // Global scope: use a temp register for catch_var
        int catch_r = 0;
        uint16_t gidx = 0;
        if (!s.catch_var.empty()) {
            gidx = chunk.addIdentifier(s.catch_var);
            catch_r = reg_top_;
            if (reg_top_ + 1 > reg_count_) reg_count_ = reg_top_ + 1;
        }

        size_t try_patch = chunk.emitJump(Op::TRY, (uint8_t)catch_r);

        for (auto& stmt : s.try_body) {
            int s2 = reg_top_;
            stmt->accept(*this);
            reg_top_ = s2;
        }

        chunk.emit(makeBx((uint8_t)Op::POP_TRY, 0));
        size_t else_patch = chunk.emitJump(Op::JUMP);

        // catch block
        uint16_t catch_addr = (uint16_t)chunk.currentPos();
        chunk.patchJump(try_patch, catch_addr);

        // Store the caught value into the global
        if (!s.catch_var.empty()) {
            chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)catch_r, gidx));
        }
        for (auto& stmt : s.catch_body) {
            int s2 = reg_top_;
            stmt->accept(*this);
            reg_top_ = s2;
        }
        size_t end_patch = chunk.emitJump(Op::JUMP);

        // else block
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
}

void Compiler::visit(const FuncDeclStmt& s) {
    // Save outer context
    auto outer_regs    = std::move(local_regs_);
    int  outer_top     = reg_top_;
    int  outer_count   = reg_count_;
    int  outer_locals  = locals_top_;
    auto outer_name    = current_func_name;

    current_func_name = s.name;
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

    FuncProto fp{func_addr, (uint8_t)n_fixed, s.variadic, defaults_idx, 0};
    uint8_t func_idx = chunk.addFunc(fp);
    func_table[s.name] = FuncInfo{func_idx, n_fixed, s.variadic};

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

    // Restore outer context
    local_regs_   = std::move(outer_regs);
    reg_top_      = outer_top;
    reg_count_    = outer_count;
    locals_top_   = outer_locals;
    current_func_name = outer_name;
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
    if (inFunction()) {
        int i_reg = local_regs_.at(s.var);

        // Compile start into i_reg
        compileInto(*s.start, i_reg);

        // Allocate end_reg above locals_top_
        int end_reg = reg_top_;
        reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        compileInto(*s.end, end_reg);

        auto loop_start = (uint16_t)chunk.currentPos();

        // Condition: LE i_reg end_reg → cond_r
        int cond_r = reg_top_;
        if (reg_top_ + 1 > reg_count_) reg_count_ = reg_top_ + 1;
        chunk.emit(makeABC((uint8_t)Op::LE, (uint8_t)cond_r, (uint8_t)i_reg, (uint8_t)end_reg));
        size_t exit_patch = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);

        break_patches.push_back({});
        for (auto& stmt : s.body) {
            int saved = reg_top_;
            stmt->accept(*this);
            reg_top_ = saved;
        }

        // Increment: use scratch at reg_top_
        int one_r = reg_top_;
        if (reg_top_ + 1 > reg_count_) reg_count_ = reg_top_ + 1;
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)one_r,
                           chunk.addConstant(Value(1.0))));
        chunk.emit(makeABC((uint8_t)Op::ADD, (uint8_t)i_reg, (uint8_t)i_reg, (uint8_t)one_r));

        chunk.emit(makeBx((uint8_t)Op::JUMP, loop_start));

        uint16_t exit = (uint16_t)chunk.currentPos();
        chunk.patchJump(exit_patch, exit);
        for (size_t p : break_patches.back()) chunk.patchJump(p, exit);
        break_patches.pop_back();

        reg_top_--;  // free end_reg
    } else {
        // Global scope: loop var and end are globals
        std::string end_var = "__for_end_" + std::to_string(for_counter_++);

        // compile start → global i
        {
            int saved = reg_top_;
            s.start->accept(*this);
            chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)last_reg_,
                               chunk.addIdentifier(s.var)));
            reg_top_ = saved;
        }
        // compile end → global end_var
        {
            int saved = reg_top_;
            s.end->accept(*this);
            chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)last_reg_,
                               chunk.addIdentifier(end_var)));
            reg_top_ = saved;
        }

        auto loop_start = (uint16_t)chunk.currentPos();

        {
            int i_r = reg_top_; reg_top_++;
            int e_r = reg_top_; reg_top_++;
            int c_r = reg_top_++; if (reg_top_ > reg_count_) reg_count_ = reg_top_;
            chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)i_r,
                               chunk.addIdentifier(s.var)));
            chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)e_r,
                               chunk.addIdentifier(end_var)));
            chunk.emit(makeABC((uint8_t)Op::LE, (uint8_t)c_r, (uint8_t)i_r, (uint8_t)e_r));
            size_t exit_patch = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)c_r);
            reg_top_ -= 3;

            break_patches.push_back({});
            for (auto& stmt : s.body) {
                int saved = reg_top_;
                stmt->accept(*this);
                reg_top_ = saved;
            }

            // increment
            {
                int r0 = reg_top_; reg_top_++;
                int r1 = reg_top_++; if (reg_top_ > reg_count_) reg_count_ = reg_top_;
                chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)r0,
                                   chunk.addIdentifier(s.var)));
                chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)r1,
                                   chunk.addConstant(Value(1.0))));
                chunk.emit(makeABC((uint8_t)Op::ADD, (uint8_t)r0, (uint8_t)r0, (uint8_t)r1));
                chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)r0,
                                   chunk.addIdentifier(s.var)));
                reg_top_ -= 2;
            }
            chunk.emit(makeBx((uint8_t)Op::JUMP, loop_start));
            uint16_t exit = (uint16_t)chunk.currentPos();
            chunk.patchJump(exit_patch, exit);
            for (size_t p : break_patches.back()) chunk.patchJump(p, exit);
            break_patches.pop_back();
        }
    }
}

// ── expressions ───────────────────────────────────────────────────────────────

void Compiler::visit(const NumberExpr& e) {
    last_reg_ = allocReg();
    chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_,
                       chunk.addConstant(Value(e.value))));
}

void Compiler::visit(const StringExpr& e) {
    last_reg_ = allocReg();
    chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_,
                       chunk.addConstant(Value(e.value))));
}

void Compiler::visit(const BoolExpr& e) {
    last_reg_ = allocReg();
    chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_,
                       chunk.addConstant(Value(e.value ? 1.0 : 0.0))));
}

void Compiler::visit(const NilExpr&) {
    last_reg_ = allocReg();
    chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)last_reg_, 0, 0));
}

void Compiler::visit(const VarExpr& e) {
    if (inFunction()) {
        auto it = local_regs_.find(e.name);
        if (it != local_regs_.end()) {
            last_reg_ = it->second;
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
        case '|': chunk.emit(makeABC((uint8_t)Op::OR,  (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
        case '&': chunk.emit(makeABC((uint8_t)Op::AND, (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR)); break;
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
        chunk.emit(makeABC((uint8_t)Op::CALL_FUNC, (uint8_t)call_base,
                           it->second.func_idx, (uint8_t)argc));
        last_reg_ = call_base;
        // reg_top_ stays at call_base + argc (will be reset by statement-level save/restore)
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

    if (e.callee == "print") {
        chunk.emit(makeABC((uint8_t)Op::CALL_PRINT, (uint8_t)call_base, (uint8_t)argc, 0));
        last_reg_ = call_base;
    } else if (e.callee == "printf") {
        chunk.emit(makeABC((uint8_t)Op::CALL_PRINTF, (uint8_t)call_base, (uint8_t)argc, 0));
        last_reg_ = call_base;
    } else if (e.callee == "assert") {
        chunk.emit(makeABC((uint8_t)Op::CALL_ASSERT, (uint8_t)call_base, (uint8_t)argc, 0));
        last_reg_ = call_base;
    } else if (e.callee == "time") {
        // time() returns into call_base
        chunk.emit(makeABC((uint8_t)Op::CALL_TIME, (uint8_t)call_base, 0, 0));
        last_reg_ = call_base;
        reg_top_ = call_base + 1;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
    } else {
        throw std::runtime_error("unknown function: " + e.callee);
    }
}

void Compiler::visit(const VarArgExpr&) {
    if (!inFunction())
        throw std::runtime_error("... outside a variadic function");
    int base = reg_top_;
    chunk.emit(makeABC((uint8_t)Op::LOAD_VARARGS, (uint8_t)base, 0, 0));
    last_reg_ = base;
}
