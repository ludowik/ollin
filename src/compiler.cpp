#include "compiler.h"
#include "modules/modules.h"
#include <algorithm>
#include <stdexcept>
#include <unordered_set>

int Compiler::resolve_upvalue(const std::string& name) {
    auto it = cur_upval_idx_.find(name);
    if (it != cur_upval_idx_.end())
        return it->second;
    if (outer_scopes_.empty())
        return -1;
    return resolve_upval_from((int)outer_scopes_.size() - 1, name);
}

int Compiler::resolve_upval_from(int scope_idx, const std::string& name) {
    OuterScope& scope = outer_scopes_[scope_idx];
    auto local_it = scope.regs.find(name);
    if (local_it != scope.regs.end())
        return capture_upval_chain(scope_idx, true, (uint8_t)local_it->second, name);
    auto uv_it = scope.upval_idx.find(name);
    if (uv_it != scope.upval_idx.end())
        return capture_upval_chain(scope_idx, false, (uint8_t)uv_it->second, name);
    if (scope_idx == 0)
        return -1;
    int outer_uv = resolve_upval_from(scope_idx - 1, name);
    if (outer_uv < 0)
        return -1;
    return capture_upval_chain(scope_idx, false, (uint8_t)outer_uv, name);
}

int Compiler::capture_upval_chain(int scope_idx, bool is_local, uint8_t idx, const std::string& name) {
    bool cur_is_local = is_local;
    uint8_t cur_idx = idx;

    // Propagate through intermediate function scopes
    for (int i = scope_idx + 1; i < (int)outer_scopes_.size(); i++) {
        OuterScope& s = outer_scopes_[i];
        auto it = s.upval_idx.find(name);
        if (it != s.upval_idx.end()) {
            cur_idx = (uint8_t)it->second;
            cur_is_local = false;
        } else if (s.func_proto_idx >= 0) {
            int uv_i = (int)chunk.funcs[s.func_proto_idx].upvals.size();
            if (uv_i > 255) // the upvalue index is an 8-bit operand
                throw std::runtime_error("function captures more than 255 upvalues");
            chunk.funcs[s.func_proto_idx].upvals.push_back({cur_is_local, cur_idx});
            s.upval_idx[name] = uv_i;
            cur_idx = (uint8_t)uv_i;
            cur_is_local = false;
        }
    }

    // Add to current function
    {
        auto it = cur_upval_idx_.find(name);
        if (it != cur_upval_idx_.end())
            return it->second;
    }
    if (current_func_idx_ < 0)
        return -1; // in main chunk, no FuncProto
    int uv_i = (int)chunk.funcs[current_func_idx_].upvals.size();
    if (uv_i > 255) // the upvalue index is an 8-bit operand
        throw std::runtime_error("function captures more than 255 upvalues");
    chunk.funcs[current_func_idx_].upvals.push_back({cur_is_local, cur_idx});
    cur_upval_idx_[name] = uv_i;
    return uv_i;
}

static Value eval_constant(const Expr& e, const std::vector<std::string>& files, SourceLoc fallback = {}) {
    if (auto* n = dynamic_cast<const NumberExpr*>(&e))
        return n->is_integer ? Value(n->ival) : num_value(n->value);
    if (auto* s = dynamic_cast<const StringExpr*>(&e))
        return Value(s->value);
    if (auto* b = dynamic_cast<const BoolExpr*>(&e))
        return Value::make_bool(b->value);
    if (dynamic_cast<const NilExpr*>(&e))
        return Value{};
    SourceLoc loc = (e.line > 0) ? e.sloc() : fallback;
    throw std::runtime_error(loc.str(files) + ": default values must be literal constants (not a runtime expression)");
}

static Op token_to_op(TokenType op) {
    switch (op) {
    case TokenType::PLUS_EQUAL:
        return Op::ADD;
    case TokenType::MINUS_EQUAL:
        return Op::SUB;
    case TokenType::STAR_EQUAL:
        return Op::MUL;
    case TokenType::SLASH_EQUAL:
        return Op::DIV;
    case TokenType::PERCENT_EQUAL:
        return Op::MOD;
    default:
        throw std::runtime_error("unknown compound index assign op");
    }
}

// Opcode of a NON short-circuit binary operator (arithmetic, comparison, bitwise). '&' and '|'
// (and/or) are excluded: they compile to short-circuit jumps (JUMP_IF_FALSE), never through this
// opcode. Shared by visit(BinaryExpr) and compile_into so the switch is not duplicated.
static Op binary_arith_opcode(char op) {
    switch (op) {
    case '+':
        return Op::ADD;
    case '-':
        return Op::SUB;
    case '*':
        return Op::MUL;
    case '/':
        return Op::DIV;
    case 'q':
        return Op::IDIV;
    case 'p':
        return Op::POW;
    case '%':
        return Op::MOD;
    case '>':
        return Op::GT;
    case '<':
        return Op::LT;
    case 'G':
        return Op::GE;
    case 'L':
        return Op::LE;
    case 'N':
        return Op::NEQ;
    case '=':
        return Op::EQ;
    case 'o':
        return Op::BOR;
    case 'b':
        return Op::BAND;
    case 'x':
        return Op::BXOR;
    case 'l':
        return Op::BLSHIFT;
    case 'r':
        return Op::BRSHIFT;
    default:
        throw std::runtime_error(std::string("unknown binary op: ") + op);
    }
}

static Op unary_opcode(char op) {
    switch (op) {
    case '-':
        return Op::NEGATE;
    case '!':
        return Op::NOT;
    case '~':
        return Op::BNOT;
    default:
        throw std::runtime_error(std::string("unknown unary op: ") + op);
    }
}

// Implicit void epilogue of a function or method. Omitted when the body already ends with a
// RETURN or RETURN_V: that last instruction returns unconditionally, so one more would be
// unreachable. This does NOT cover an explicit valueless `return`, which is always emitted.
static void emit_implicit_return(Chunk& chunk) {
    if (!chunk.code.empty()) {
        Op last = (Op)i_op(chunk.code.back());
        if (last == Op::RETURN || last == Op::RETURN_V)
            return;
    }
    chunk.emit(make_abc((uint8_t)Op::RETURN, 0, 0, 0));
}

// collect_funcs=true inside function bodies (nested FuncDecls need a local register)
// collect_funcs=false at top level (top-level funcs are accessed via func_table)
struct CollectLocalsVisitor : StmtQuery {
    std::vector<std::string>& out;
    std::unordered_set<std::string>& seen;
    bool collect_funcs;
    const std::vector<std::string>& files;
    std::unordered_set<std::string>* funcs; // the names of the local functions, bound straight away, when asked for

    CollectLocalsVisitor(std::vector<std::string>& out, std::unordered_set<std::string>& seen, bool collect_funcs,
                         const std::vector<std::string>& files, std::unordered_set<std::string>* funcs)
        : out(out), seen(seen), collect_funcs(collect_funcs), files(files), funcs(funcs) {
    }

    void visit(const VarDeclStmt& s) override {
        if (!s.is_global) { // 'global' goes to the globals table, with no register;
                            // 'constant' is an ordinary local, immutable at compile time
            for (auto& n : s.names) {
                if (!seen.insert(n).second) {
                    throw std::runtime_error(s.sloc().str(files) + ": local variable '" + n +
                                             "' already declared in this scope");
                }
                out.push_back(n);
            }
        }
    }
    void visit(const FuncDeclStmt& s) override {
        // Do not descend into the body: a function's locals live in its own scope.
        if (collect_funcs && seen.insert(s.name).second) {
            out.push_back(s.name);
            if (funcs)
                funcs->insert(s.name);
        }
    }
    // User blocks have strict lexical scope, so we do not descend: each block's locals are
    // collected separately in compile_block.
    void visit(const ForIterStmt&) override {
    }
    void visit(const WhileStmt&) override {
    }
    void visit(const IfStmt&) override {
    }
    void visit(const TryCatchStmt&) override {
    }
    void visit(const DoStmt&) override {
    }
    void visit(const SwitchStmt&) override {
    }
    // A BlockStmt is an internal container (import) with no scope of its own, so descend.
    void visit(const BlockStmt& s) override {
        run(s.stmts);
    }
};

static void collect_locals(const std::vector<std::unique_ptr<Stmt>>& stmts, std::vector<std::string>& out,
                           const std::vector<std::string>& files, bool collect_funcs = true,
                           std::unordered_set<std::string>* funcs = nullptr) {
    std::unordered_set<std::string> seen(out.begin(), out.end());
    CollectLocalsVisitor v(out, seen, collect_funcs, files, funcs);
    v.run(stmts);
}

// Globals declared with 'global' are visible everywhere, wherever the declaration sits, so
// they are all collected before compilation — including those nested inside functions.
struct CollectGlobalsVisitor : StmtQuery {
    std::unordered_set<std::string>& out;
    std::unordered_set<std::string>& enums;
    const std::vector<std::string>& files;

    CollectGlobalsVisitor(std::unordered_set<std::string>& out, std::unordered_set<std::string>& enums,
                          const std::vector<std::string>& files)
        : out(out), enums(enums), files(files) {
    }

    // The tree's topology is declared by the nodes themselves (Stmt::for_each_body, ast.h)
    // rather than re-enumerated here, so a new statement with a body is walked without touching
    // this visitor. The `visit` methods below only COLLECT.
    void walk(const std::vector<std::unique_ptr<Stmt>>& stmts) {
        for (auto& s : stmts) {
            s->accept(*this);
            s->for_each_body([this](const std::vector<std::unique_ptr<Stmt>>& sub) { walk(sub); });
        }
    }

    void visit(const VarDeclStmt& s) override {
        if (s.is_global) {
            for (auto& n : s.names) {
                if (!out.insert(n).second) {
                    throw std::runtime_error(s.sloc().str(files) + ": global variable '" + n + "' already declared");
                }
            }
        }
    }
    void visit(const EnumDeclStmt& s) override {
        if (!s.obj_expr) {
            out.insert(s.name); // an enum under a bare name is a global, like a class
            enums.insert(s.name);
        }
    }
    void visit(const ClassDeclStmt& s) override {
        out.insert(s.name); // a class is visible to its own methods
    }
};

static void collect_globals(const std::vector<std::unique_ptr<Stmt>>& stmts, std::unordered_set<std::string>& out,
                            std::unordered_set<std::string>& enums, const std::vector<std::string>& files) {
    CollectGlobalsVisitor v(out, enums, files);
    v.walk(stmts);
}

// The negation of a numeric LITERAL is a constant: `-1` used to cost a LOAD_K plus a NEGATE at
// every execution. Integer wrap-around is the same as the VM's, so -(INT64_MIN) is unchanged.
static bool negated_literal(const UnaryExpr& e, Value& out) {
    if (e.op != '-')
        return false;
    auto* n = dynamic_cast<const NumberExpr*>(e.operand.get());
    if (!n)
        return false;
    out = n->is_integer ? Value((int64_t)(0 - (uint64_t)n->ival)) : num_value(-n->value);
    return true;
}

void Compiler::compile_into(const Expr& e, int dest, bool dest_at_top) {
    // The direct paths below need dest < reg_top_, so that operand temporaries never overlap it.
    if (dest_at_top)
        reserve_regs_to(dest + 1);
    if (auto* n = dynamic_cast<const NumberExpr*>(&e)) {
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)dest,
                            chunk.add_constant(n->is_integer ? Value(n->ival) : num_value(n->value))));
    } else if (auto* s = dynamic_cast<const StringExpr*>(&e)) {
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)dest, chunk.add_constant(Value(s->value))));
    } else if (auto* b = dynamic_cast<const BoolExpr*>(&e)) {
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)dest, chunk.add_constant(Value::make_bool(b->value))));
    } else if (dynamic_cast<const NilExpr*>(&e)) {
        chunk.emit(make_abc((uint8_t)Op::LOAD_NIL, (uint8_t)dest, 0, 0));
    } else if (auto* bin = dynamic_cast<const BinaryExpr*>(&e); bin && bin->op != '&' && bin->op != '|') {
        // Non short-circuit binary: emit the FINAL op straight into dest, with no temporary and
        // no MOVE. This is safe because a 3-address instruction reads r_l and r_r BEFORE writing
        // dest, so aliasing is harmless even when dest is also an operand (a = a - b gives
        // SUB Ra,Ra,Rb). Every caller has dest < reg_top_, so operand temporaries — allocated
        // from reg_top_ up — never overlap dest.
        int saved = reg_top_;
        bin->left->accept(*this);
        int r_l = last_reg_;
        if (reg_top_ <= r_l) // protects r_l from a 0-argument call (see visit(BinaryExpr))
            reserve_regs_to(r_l + 1);
        bin->right->accept(*this);
        int r_r = last_reg_;
        chunk.emit(make_abc((uint8_t)binary_arith_opcode(bin->op), (uint8_t)dest, (uint8_t)r_l, (uint8_t)r_r));
        reg_top_ = saved;
        last_reg_ = dest;
    } else if (auto* un = dynamic_cast<const UnaryExpr*>(&e)) {
        Value folded;
        if (negated_literal(*un, folded)) {
            chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)dest, chunk.add_constant(folded)));
            last_reg_ = dest;
            return;
        }
        // Unary: emit into dest directly, safe for the same reason with a single operand.
        int saved = reg_top_;
        un->operand->accept(*this);
        int r_in = last_reg_;
        chunk.emit(make_abc((uint8_t)unary_opcode(un->op), (uint8_t)dest, (uint8_t)r_in, 0));
        reg_top_ = saved;
        last_reg_ = dest;
    } else {
        int saved = reg_top_;
        if (dest_at_top)
            reg_top_ = dest; // a call, a map, an array MAY land on dest, and then needs no MOVE
        e.accept(*this);
        if (last_reg_ != dest)
            chunk.emit(make_abc((uint8_t)Op::MOVE, (uint8_t)dest, (uint8_t)last_reg_, 0));
        reg_top_ = saved;
    }
}

Chunk Compiler::compile(const Program& prog) {
    chunk.source_files = prog.source_files;
    reg_top_ = 0;
    reg_count_ = 8;
    collect_globals(prog.stmts, declared_globals_, enum_names_, chunk.source_files);
    for (auto& n : builtin_module_names())
        declared_globals_.insert(n);
    for (auto& n : builtin_func_names())
        declared_globals_.insert(n);
    declared_globals_.insert("deltaTime");
    declared_globals_.insert("elapsedTime");
    declared_globals_.insert("W");  // the width of the render area, window.width by default
    declared_globals_.insert("H");  // the height of the render area, window.height by default
    declared_globals_.insert("CX"); // the render area's centre X (W / 2)
    declared_globals_.insert("CY"); // the render area's centre Y (H / 2)
    // Pre-scan all top-level var/for declarations → registers (like Lua's local in main chunk)
    // collect_funcs=false: top-level functions are in func_table, not in local registers
    std::vector<std::string> top_locals;
    collect_locals(prog.stmts, top_locals, chunk.source_files, false);
    bind_scan_locals(top_locals, {}); // collect_funcs=false: no function here, everything is deferred
    locals_top_ = reg_top_;
    bump_reg_count();

    for (auto& s : prog.stmts)
        s->accept(*this);
    // Same guard as for functions: registers are 8-bit operands, and without it a top-level
    // script needing more than 255 of them was silently truncated.
    if (reg_count_ > 255)
        throw std::runtime_error(sloc().str(chunk.source_files) + ": top-level code uses more than 255 registers");
    chunk.top_reg_count = (uint8_t)reg_count_; // reg_count_ starts at 8 and only ever grows
    chunk.emit(make_bx((uint8_t)Op::HALT, 0));
    if (chunk.code.size() > 65535)
        throw std::runtime_error(sloc().str(chunk.source_files) + ": program too large (> 65535 instructions)");
    return std::move(chunk);
}

// True when the expression is a call, in any form. Used by multi-return destructuring, which
// must read several values from the call base.
static bool is_call_node(const Expr* e) {
    return dynamic_cast<const CallExpr*>(e) || dynamic_cast<const ExprCallExpr*>(e) ||
           dynamic_cast<const MethodCallExpr*>(e);
}

// Expression that may produce SEVERAL values when it sits last in a list (call arguments,
// array elements, return, destructuring): `...` or a call. Anywhere else it is adjusted to a
// single value.
static bool is_multi_value_expr(const Expr* e) {
    return dynamic_cast<const VarArgExpr*>(e) || is_call_node(e);
}

void Compiler::visit(const VarDeclStmt& s) {
    note_line(s.line, s.file_idx);

    // Activates a deferred local by moving it from pending_var_reg_ to local_regs_, which is
    // where lexical scope begins for it, and returns its register. Call it only AFTER compiling
    // the initializers, so that `var a = a` reads the outer `a` and not the local being
    // declared.
    auto activate_local = [&](const std::string& name) -> int {
        auto it = pending_var_reg_.find(name);
        if (it == pending_var_reg_.end())
            return local_regs_.at(name); // already active
        int reg = it->second;
        pending_var_reg_.erase(it);
        local_regs_[name] = reg;
        return reg;
    };
    // A const is registered HERE and not at the end of the function: the multi-return path
    // returns early, and `const a, b = f()` silently lost its constness.
    if (s.is_constant)
        for (auto& n : s.names)
            const_names_.insert(n);
    // Register reserved for a still-deferred local, without activating it.
    auto reserved_reg = [&](const std::string& name) -> int {
        auto it = pending_var_reg_.find(name);
        return it != pending_var_reg_.end() ? it->second : local_regs_.at(name);
    };

    // Multi-return: several targets and a single value that is a CALL, in any form — named
    // function, closure, dynamic call, method. The call is compiled at a known base where the VM
    // leaves all its return values (RETURN copies R[A..A+k-1] to base..base+k-1), and we then
    // read base+i.
    // This generalizes the earlier path, which only handled a named CALL_FUNC — hence a crash
    // on closures and lost values for methods and dynamic calls.
    if (s.names.size() > 1 && s.values.size() == 1 && is_multi_value_expr(s.values[0].get())) {
        int base = reg_top_;
        int n = (int)s.names.size();
        if (dynamic_cast<const VarArgExpr*>(s.values[0].get())) {
            // var a, b = ... gives n varargs at base, nil-padded, with last_results_ = n
            chunk.emit(make_abc((uint8_t)Op::LOAD_VARARGS, (uint8_t)base, (uint8_t)n, 0));
        } else {
            s.values[0]->accept(*this); // a call: k return values, last_results_ = k
            if (last_reg_ != base)      // the call itself spread, so recompose at base
                chunk.emit(make_abc((uint8_t)Op::MOVE_RESULTS, (uint8_t)base, (uint8_t)last_reg_, 0));
        }
        if (base + n > reg_count_)
            reg_count_ = base + n; // these registers are live, read just below
        // Nil out the targets beyond what the call returned (k < n): otherwise they would read
        // stale registers, and `var a, b = len(x)` must leave b nil.
        chunk.emit(make_abc((uint8_t)Op::SPREAD_RESULTS, (uint8_t)base, (uint8_t)n, 0));
        for (int i = 0; i < n; ++i) {
            if (s.is_global) {
                chunk.emit(make_abx((uint8_t)Op::STORE_GLOBAL, (uint8_t)(base + i), chunk.add_identifier(s.names[i])));
            } else {
                int dest = activate_local(s.names[i]); // the call is compiled, so this is safe
                if (base + i != dest)
                    chunk.emit(make_abc((uint8_t)Op::MOVE, (uint8_t)dest, (uint8_t)(base + i), 0));
            }
        }
        reg_top_ = base;
        return;
    }

    // 'global' declaration → store into the VM-wide globals table
    if (s.is_global) {
        // Normal: parallel assignment (or nil when no value)
        for (int i = 0; i < (int)s.names.size(); ++i) {
            int saved = reg_top_;
            int src = alloc_reg();
            if (i < (int)s.values.size()) {
                compile_into(*s.values[i], src);
            } else {
                chunk.emit(make_abc((uint8_t)Op::LOAD_NIL, (uint8_t)src, 0, 0));
            }
            chunk.emit(make_abx((uint8_t)Op::STORE_GLOBAL, (uint8_t)src, chunk.add_identifier(s.names[i])));
            reg_top_ = saved;
        }
        return;
    }

    // Compile every initializer into its reserved register while the local is NOT yet active,
    // so that `var a = a` reads the outer `a`. Every target's initializer therefore sees the
    // scope as it was before the declaration.
    for (int i = 0; i < (int)s.names.size(); ++i) {
        int dest = reserved_reg(s.names[i]);
        if (i < (int)s.values.size()) {
            compile_into(*s.values[i], dest);
        } else {
            chunk.emit(make_abc((uint8_t)Op::LOAD_NIL, (uint8_t)dest, 0, 0));
        }
    }
    // With the initializers compiled, the locals become visible from here on.
    for (auto& n : s.names)
        activate_local(n);
}

static bool body_has_func(const std::vector<std::unique_ptr<Stmt>>& body); // defined below

// The temporaries of a statement are freed once it is compiled, so the next one reuses them.
void Compiler::compile_stmt_seq(const std::vector<std::unique_ptr<Stmt>>& body) {
    for (auto& stmt : body) {
        int saved = reg_top_;
        stmt->accept(*this);
        reg_top_ = saved;
    }
}

void Compiler::bind_scan_locals(const std::vector<std::string>& names, const std::unordered_set<std::string>& funcs,
                                const std::unordered_set<std::string>& skip) {
    for (auto& name : names) {
        if (skip.count(name))
            continue; // the current scope's prologue (a parameter, self, a catch variable): already bound
        if (funcs.count(name))
            local_regs_[name] =
                reg_top_++; // a local function is visible straight away, for recursion and forward references
        else
            pending_var_reg_[name] = reg_top_++; // var and const are deferred until their declaration
    }
}

// Registers to keep reserved after a loop. A closure in the body may capture the loop variable
// AND the body's locals: their upvalues stay OPEN — they point into the registers — until the
// frame returns, so handing those registers back to temporaries would overwrite the captured
// values. compile_block has already reserved the body's locals (the current reg_top_), and we
// keep the higher of the two.
bool Compiler::body_carries_func(const std::vector<std::unique_ptr<Stmt>>& body) {
    auto it = has_func_cache_.find(&body);
    if (it != has_func_cache_.end())
        return it->second;
    bool r = body_has_func(body);
    has_func_cache_.emplace(&body, r);
    return r;
}

int Compiler::keep_captured_regs(const std::vector<std::unique_ptr<Stmt>>& body, int loop_vars_top, int recycled_top,
                                 int reg_top_after_body) {
    if (!body_carries_func(body))
        return recycled_top;
    return loop_vars_top > reg_top_after_body ? loop_vars_top : reg_top_after_body;
}

void Compiler::compile_block(const std::vector<std::unique_ptr<Stmt>>& body, const std::string& pre_bound,
                             int pre_bound_reg) {
    auto saved_regs = local_regs_;
    auto saved_pending = pending_var_reg_;
    // The constants belong to the scope too: without this, `do const x = 1 end` then `var x = 2`
    // refused to assign x, a name with nothing to do with the block's.
    auto saved_consts = const_names_;
    int saved_top = reg_top_;
    int saved_locals = locals_top_;

    static const std::unordered_set<std::string> no_skip;
    std::unordered_set<std::string> skip;
    if (!pre_bound.empty()) {
        local_regs_[pre_bound] = pre_bound_reg;
        skip.insert(pre_bound);
    }
    std::vector<std::string> block_locals;
    std::unordered_set<std::string> block_funcs;
    collect_locals(body, block_locals, chunk.source_files, true, &block_funcs);
    bind_scan_locals(block_locals, block_funcs, pre_bound.empty() ? no_skip : skip);
    int block_locals_top = reg_top_;
    locals_top_ = block_locals_top;
    bump_reg_count();

    compile_stmt_seq(body);

    bool has_func = body_carries_func(body);
    // A block's locals DIE at its end, so the upvalues opened on them are closed there — the
    // value is copied into the Upvalue and the register stops being watched. Without this, a
    // closure declared in a nested block kept an open upvalue on a register that went back to
    // the temporaries, and the next statement overwrote the captured value (a `do` block
    // returning nil instead of 42, measured). The two loop forms already close per iteration,
    // for the same reason; reserving the registers instead would grow without bound over a file.
    if (has_func && reg_top_ > saved_top)
        chunk.emit(make_abc((uint8_t)Op::CLOSE_UPVALS, (uint8_t)saved_top, 0, 0));
    local_regs_ = std::move(saved_regs);
    pending_var_reg_ = std::move(saved_pending);
    const_names_ = std::move(saved_consts);
    reg_top_ = has_func ? block_locals_top : saved_top;
    locals_top_ = saved_locals;
}

void Compiler::visit(const WhileStmt& s) {
    note_line(s.line, s.file_idx);
    auto loop_start = (uint16_t)chunk.current_pos();
    int saved = reg_top_;
    s.cond->accept(*this);
    int cond_r = last_reg_;
    size_t exit_patch = chunk.emit_jump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);
    reg_top_ = saved;

    break_patches.push_back({{}, outer_scopes_.size(), try_depth_, false});
    continue_patches.push_back({{}, outer_scopes_.size(), try_depth_, false});
    compile_block(s.body);
    for (size_t p : continue_patches.back().patches)
        chunk.patch_jump(p, loop_start);
    continue_patches.pop_back();
    chunk.emit(make_bx((uint8_t)Op::JUMP, loop_start));
    chunk.patch_jump(exit_patch, (uint16_t)chunk.current_pos());
    for (size_t p : break_patches.back().patches)
        chunk.patch_jump(p, (uint16_t)chunk.current_pos());
    break_patches.pop_back();
}

void Compiler::visit(const IfStmt& s) {
    note_line(s.line, s.file_idx);
    std::vector<size_t> end_patches;

    int saved = reg_top_;
    s.cond->accept(*this);
    int cond_r = last_reg_;
    reg_top_ = saved;
    size_t next_patch = chunk.emit_jump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);

    // The jump to the end is only needed when a branch FOLLOWS: without one it lands on the
    // next instruction, and that dead jump was executed every time the branch was taken.
    bool has_more = !s.else_ifs.empty() || !s.else_body.empty();
    compile_block(s.then_body);
    if (has_more)
        end_patches.push_back(chunk.emit_jump(Op::JUMP));

    for (size_t k = 0; k < s.else_ifs.size(); ++k) {
        auto& ei = s.else_ifs[k];
        chunk.patch_jump(next_patch, (uint16_t)chunk.current_pos());
        int s2 = reg_top_;
        ei.cond->accept(*this);
        int er = last_reg_;
        reg_top_ = s2;
        next_patch = chunk.emit_jump(Op::JUMP_IF_FALSE, (uint8_t)er);
        compile_block(ei.body);
        if (k + 1 < s.else_ifs.size() || !s.else_body.empty())
            end_patches.push_back(chunk.emit_jump(Op::JUMP));
    }

    chunk.patch_jump(next_patch, (uint16_t)chunk.current_pos());
    compile_block(s.else_body);

    uint16_t end_addr = (uint16_t)chunk.current_pos();
    for (size_t p : end_patches)
        chunk.patch_jump(p, end_addr);
}

void Compiler::visit(const SwitchStmt& s) {
    note_line(s.line, s.file_idx);

    int saved = reg_top_;
    s.subject->accept(*this);
    int subj_r = last_reg_;
    // Reserve the subject's register: a 0-argument call as subject leaves reg_top_ == subj_r,
    // so without this guard evaluating the 'case' values would reallocate over the subject and
    // the wrong branch would be taken. `switch f()` is the case in point.
    if (reg_top_ <= subj_r)
        reserve_regs_to(subj_r + 1);
    int above_subj = reg_top_; // subj_r stays live through every arm

    std::vector<size_t> end_patches;
    break_patches.push_back(
        {{}, outer_scopes_.size(), try_depth_, true}); // marks the switch; a break inside it is refused

    for (auto& arm : s.cases) {
        std::vector<size_t> body_patches;
        size_t next_arm_patch = 0;

        for (size_t vi = 0; vi < arm.values.size(); ++vi) {
            bool is_last = (vi == arm.values.size() - 1);
            reg_top_ = above_subj;
            arm.values[vi]->accept(*this);
            int val_r = last_reg_;
            int cond_r = alloc_reg(); // alloc_reg() updates reg_count_
            reg_top_ = above_subj;    // frees the temporary after EQ
            chunk.emit(make_abc((uint8_t)Op::EQ, (uint8_t)cond_r, (uint8_t)subj_r, (uint8_t)val_r));
            if (!is_last) {
                size_t skip = chunk.emit_jump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);
                body_patches.push_back(chunk.emit_jump(Op::JUMP));
                chunk.patch_jump(skip, (uint16_t)chunk.current_pos());
            } else {
                next_arm_patch = chunk.emit_jump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);
            }
        }

        uint16_t body_addr = (uint16_t)chunk.current_pos();
        for (size_t p : body_patches)
            chunk.patch_jump(p, body_addr);

        reg_top_ = above_subj;
        compile_block(arm.body);
        end_patches.push_back(chunk.emit_jump(Op::JUMP));
        chunk.patch_jump(next_arm_patch, (uint16_t)chunk.current_pos());
    }

    reg_top_ = above_subj;
    compile_block(s.else_body);

    uint16_t end_addr = (uint16_t)chunk.current_pos();
    for (size_t p : end_patches)
        chunk.patch_jump(p, end_addr);
    for (size_t p : break_patches.back().patches)
        chunk.patch_jump(p, end_addr);
    break_patches.pop_back();
    reg_top_ = saved;
}

// A break and a continue jump to an address of the CURRENT function, so the innermost frame must
// have been opened in it: a `break` written inside a lambda declared in a loop used to compile,
// and jumped into the enclosing function's code — the loop's body was skipped outright, silently.
void Compiler::check_jump_scope(const Stmt& s, const std::vector<JumpTargets>& frames, const char* what) {
    if (frames.empty() || frames.back().func_depth != outer_scopes_.size())
        throw std::runtime_error(s.sloc().str(chunk.source_files) + ": " + what + " outside loop");
}

// A jump that leaves try blocks behind must POP their handlers: jumping over the POP_TRY left them
// on the VM's stack, and an error raised long after the loop was caught by them — the catch block
// ran once per iteration the loop had made, then the error reached the engine anyway.
void Compiler::pop_crossed_tries(const JumpTargets& frame) {
    for (int i = frame.try_depth; i < try_depth_; ++i)
        chunk.emit(make_bx((uint8_t)Op::POP_TRY, 0));
}

void Compiler::visit(const BreakStmt& s) {
    check_jump_scope(s, break_patches, "break");
    // A case does not fall through, so a break at the end of an arm has nothing to leave, and one
    // meant for the loop would be caught by the switch instead — silently, the loop carrying on.
    // Refusing it is the only reading that cannot mislead.
    if (break_patches.back().is_switch)
        throw std::runtime_error(s.sloc().str(chunk.source_files) +
                                 ": break inside a switch (a case does not fall through; to leave the "
                                 "enclosing loop, use a flag or return)");
    pop_crossed_tries(break_patches.back());
    break_patches.back().patches.push_back(chunk.emit_jump(Op::JUMP));
}

void Compiler::visit(const ContinueStmt& s) {
    // A continue is NOT caught by a switch: it legitimately reaches the enclosing loop.
    check_jump_scope(s, continue_patches, "continue");
    pop_crossed_tries(continue_patches.back());
    continue_patches.back().patches.push_back(chunk.emit_jump(Op::JUMP));
}

void Compiler::visit(const AssignStmt& s) {
    note_line(s.line, s.file_idx);
    if (const_names_.count(s.name))
        throw std::runtime_error(where(s) + ": cannot assign to const '" + s.name + "'");
    // Also block assignment when name is a constant captured from an outer scope
    for (auto& scope : outer_scopes_)
        if (scope.consts.count(s.name))
            throw std::runtime_error(where(s) + ": cannot assign to const '" + s.name + "'");
    {
        auto it = local_regs_.find(s.name);
        if (it != local_regs_.end()) {
            int dest = it->second;
            if (s.op == '\0') {
                compile_into(*s.value, dest);
            } else {
                // Compound: rhs is fully evaluated before writing back to dest
                int saved = reg_top_;
                s.value->accept(*this);
                int rhs = last_reg_;
                // Emit op directly into dest — safe: rhs is already in a register
                chunk.emit(make_abc((uint8_t)binary_arith_opcode(s.op), (uint8_t)dest, (uint8_t)dest, (uint8_t)rhs));
                reg_top_ = saved;
            }
            return;
        }
    }
    // Upvalue
    {
        int uv = resolve_upvalue(s.name);
        if (uv >= 0) {
            int saved = reg_top_;
            if (s.op == '\0') {
                s.value->accept(*this);
                chunk.emit(make_abc((uint8_t)Op::SET_UPVAL, (uint8_t)last_reg_, (uint8_t)uv, 0));
            } else {
                int cur = alloc_reg();
                chunk.emit(make_abc((uint8_t)Op::GET_UPVAL, (uint8_t)cur, (uint8_t)uv, 0));
                s.value->accept(*this);
                int rhs = last_reg_;
                int res = alloc_reg();
                bump_reg_count();
                chunk.emit(make_abc((uint8_t)binary_arith_opcode(s.op), (uint8_t)res, (uint8_t)cur, (uint8_t)rhs));
                chunk.emit(make_abc((uint8_t)Op::SET_UPVAL, (uint8_t)res, (uint8_t)uv, 0));
            }
            reg_top_ = saved;
            return;
        }
    }
    // Global variable (declared with 'global') → store into the globals table
    if (declared_globals_.count(s.name)) {
        int saved = reg_top_;
        if (s.op == '\0') {
            s.value->accept(*this);
            chunk.emit(make_abx((uint8_t)Op::STORE_GLOBAL, (uint8_t)last_reg_, chunk.add_identifier(s.name)));
        } else {
            int cur = alloc_reg();
            chunk.emit(make_abx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)cur, chunk.add_identifier(s.name)));
            s.value->accept(*this);
            int rhs = last_reg_;
            int res = alloc_reg();
            bump_reg_count();
            chunk.emit(make_abc((uint8_t)binary_arith_opcode(s.op), (uint8_t)res, (uint8_t)cur, (uint8_t)rhs));
            chunk.emit(make_abx((uint8_t)Op::STORE_GLOBAL, (uint8_t)res, chunk.add_identifier(s.name)));
        }
        reg_top_ = saved;
        return;
    }
    // Global scope — assignment without var/global is not allowed
    throw std::runtime_error(where(s) + ": undeclared variable '" + s.name + "' (use 'var' or 'global')");
}

void Compiler::visit(const ExprStmt& s) {
    note_line(s.line, s.file_idx);
    int saved = reg_top_;
    s.expr->accept(*this);
    reg_top_ = saved;
}

void Compiler::visit(const ThrowStmt& s) {
    note_line(s.line, s.file_idx);
    int saved = reg_top_;
    s.value->accept(*this);
    int r = last_reg_;
    chunk.emit(make_abc((uint8_t)Op::THROW, (uint8_t)r, 0, 0));
    reg_top_ = saved;
}

void Compiler::visit(const TryCatchStmt& s) {
    note_line(s.line, s.file_idx);
    int saved_top = reg_top_;

    // catch_r must be known before TRY is emitted, so it is pre-allocated as a temporary.
    int catch_r = 0;
    if (!s.catch_var.empty()) {
        catch_r = reg_top_++;
        bump_reg_count();
    }

    size_t try_patch = chunk.emit_jump(Op::TRY, (uint8_t)catch_r);
    // The handler is live for the BODY only: unwind_to_handler pops it before the catch runs, and
    // the else body comes after POP_TRY. So only the body raises the depth a jump has to undo.
    int try_base = reg_top_;
    ++try_depth_;
    compile_block(s.try_body);
    --try_depth_;
    chunk.emit(make_bx((uint8_t)Op::POP_TRY, 0));
    size_t else_patch = chunk.emit_jump(Op::JUMP);

    chunk.patch_jump(try_patch, (uint16_t)chunk.current_pos());
    // A throw LEAVES the body without running its end, so the block's own CLOSE_UPVALS never
    // executes: it is emitted again here, where control lands. The body's locals are dead at
    // this point, and one declared BEFORE the try keeps its open upvalue (its register is below
    // try_base).
    if (body_carries_func(s.try_body))
        chunk.emit(make_abc((uint8_t)Op::CLOSE_UPVALS, (uint8_t)try_base, 0, 0));

    // Catch block: catch_var keeps catch_r, other locals are scoped as usual.
    compile_block(s.catch_body, s.catch_var, catch_r);

    size_t end_patch = chunk.emit_jump(Op::JUMP);
    chunk.patch_jump(else_patch, (uint16_t)chunk.current_pos());
    compile_block(s.else_body);
    chunk.patch_jump(end_patch, (uint16_t)chunk.current_pos());

    if (!body_carries_func(s.try_body) && !body_carries_func(s.catch_body) && !body_carries_func(s.else_body))
        reg_top_ = saved_top;
}

Compiler::FuncScope::FuncScope(Compiler& comp, const std::string& fname)
    : c(comp), regs(std::move(comp.local_regs_)), pending(std::move(comp.pending_var_reg_)),
      upvals(std::move(comp.cur_upval_idx_)), consts(comp.const_names_), top(comp.reg_top_), count(comp.reg_count_),
      locals(comp.locals_top_), fidx(comp.current_func_idx_), name(comp.current_func_name) {
    c.outer_scopes_.push_back({regs, upvals, consts, fidx}); // for upvalue resolution
    c.try_floors_.push_back(c.try_depth_);                   // this body's returns are relative to HERE
    c.const_names_.clear();
    c.current_func_name = fname;
    c.cur_upval_idx_.clear();
    c.local_regs_.clear();
    c.pending_var_reg_.clear();
    c.reg_top_ = 0;
    c.reg_count_ = 0;
    c.locals_top_ = 0;
}

Compiler::FuncScope::~FuncScope() {
    c.outer_scopes_.pop_back();
    c.try_floors_.pop_back();
    c.local_regs_ = std::move(regs);
    c.pending_var_reg_ = std::move(pending);
    c.cur_upval_idx_ = std::move(upvals);
    c.const_names_ = std::move(consts);
    c.reg_top_ = top;
    c.reg_count_ = count;
    c.locals_top_ = locals;
    c.current_func_name = name;
    c.current_func_idx_ = fidx;
}

uint8_t Compiler::compile_func_body(const std::string& name, const std::vector<std::string>& params,
                                    const std::vector<std::unique_ptr<Expr>>& defaults,
                                    const std::vector<std::unique_ptr<Stmt>>& body, bool variadic, bool is_static,
                                    bool with_self, SourceLoc defaults_loc,
                                    const std::function<void(uint8_t)>& on_registered) {
    FuncScope scope(*this, name);

    // Instance method: self in R[0], parameters from R[1]. Otherwise parameters from R[0].
    int n_params = (int)params.size();
    int first = with_self ? 1 : 0;
    int n_fixed = n_params + first;
    if (with_self)
        local_regs_["self"] = 0;
    for (int i = 0; i < n_params; ++i)
        local_regs_[params[i]] = i + first;
    reg_top_ = n_fixed;

    // The prologue names seed the pre-scan, so redeclaring a parameter with 'var' is caught, and
    // they go in `skip` because they already have their register.
    std::vector<std::string> body_locals;
    std::unordered_set<std::string> skip(params.begin(), params.end());
    if (with_self) {
        body_locals.push_back("self");
        skip.insert("self");
    }
    body_locals.insert(body_locals.end(), params.begin(), params.end());
    std::unordered_set<std::string> body_funcs;
    collect_locals(body, body_locals, chunk.source_files, true, &body_funcs);
    bind_scan_locals(body_locals, body_funcs, skip);
    locals_top_ = reg_top_;
    reg_count_ = reg_top_;

    size_t jump_patch = chunk.emit_jump(Op::JUMP); // over the body, which is inlined here
    uint32_t func_addr = (uint32_t)chunk.current_pos();

    // Defaults: for an instance method index 0 is self, which has none.
    std::vector<Value> defs(n_fixed);
    for (int i = 0; i < n_params; ++i)
        defs[i + first] = (i < (int)defaults.size() && defaults[i])
                              ? eval_constant(*defaults[i], chunk.source_files, defaults_loc)
                              : Value{};
    uint16_t defaults_idx = chunk.add_func_defaults(std::move(defs));

    FuncProto fp{func_addr, (uint8_t)n_fixed, variadic, is_static, defaults_idx, 0, {}};
    uint8_t func_idx = chunk.add_func(fp);
    current_func_idx_ = func_idx;
    if (on_registered)
        on_registered(func_idx);

    compile_stmt_seq(body);
    emit_implicit_return(chunk); // an implicit void return, omitted when the body already ends with RETURN

    if (reg_count_ > 255)
        throw std::runtime_error(sloc().str(chunk.source_files) + ": function uses more than 255 registers");
    chunk.funcs[func_idx].reg_count = (uint8_t)reg_count_;
    chunk.patch_jump(jump_patch, (uint16_t)chunk.current_pos());
    return func_idx;
}

void Compiler::visit(const FuncDeclStmt& s) {
    note_line(s.line, s.file_idx);
    // The question is not "am I inside a function" but "does this name have a local register
    // here" — collect_locals reserves one for a func declared in a BLOCK, top level included.
    // Deciding by in_function() compiled a `func` inside a top-level `do` as a global while
    // binding it as a local, so its register stayed empty: `var g = h` gave nil.
    bool is_local = local_regs_.count(s.name) != 0;
    uint8_t func_idx =
        compile_func_body(s.name, s.params, s.defaults, s.body, s.variadic, false, false, s.sloc(), [&](uint8_t idx) {
            // A global function is pre-registered in func_table so recursive calls are optimized
            // (CALL_DYN instead of CALL_FUNC when the function may be a closure). One living in
            // a local register gets no entry.
            if (!is_local)
                func_table[s.name] =
                    FuncInfo{idx, (int)s.params.size(), s.variadic, !outer_scopes_.back().regs.empty()};
        });

    bool has_upvals = !chunk.funcs[func_idx].upvals.empty();

    if (is_local) {
        // Stored in the local register pre-allocated by collect_locals, with no func_table entry
        // and no access to globals.
        int dest = local_regs_.at(s.name);
        chunk.emit(make_abx(has_upvals ? (uint8_t)Op::MAKE_CLOSURE : (uint8_t)Op::LOAD_FUNC, (uint8_t)dest, func_idx));
        return;
    }
    // Top level: LOAD_FUNC (or MAKE_CLOSURE) then STORE_GLOBAL. Needed even without outer
    // variables, so that get_global("draw") works (the WASM auto-detection) and so the function
    // is reachable as a value.
    func_table[s.name].is_closure = has_upvals;
    int tmp = alloc_reg();
    chunk.emit(make_abx(has_upvals ? (uint8_t)Op::MAKE_CLOSURE : (uint8_t)Op::LOAD_FUNC, (uint8_t)tmp, func_idx));
    chunk.emit(make_abx((uint8_t)Op::STORE_GLOBAL, (uint8_t)tmp, chunk.add_identifier(s.name)));
    reg_top_--;
}

void Compiler::visit(const FuncExpr& s) {
    uint8_t func_idx = compile_func_body("<lambda>", s.params, s.defaults, s.body, s.variadic, false, false, s.sloc());
    bool has_upvals = !chunk.funcs[func_idx].upvals.empty();
    int dest = alloc_reg();
    chunk.emit(make_abx(has_upvals ? (uint8_t)Op::MAKE_CLOSURE : (uint8_t)Op::LOAD_FUNC, (uint8_t)dest, func_idx));
    last_reg_ = dest;
}

// Compiles each expression into base+i. These are the argument slots of a call and the values
// of a return: the TOP of the scratch area, so compile_into can write the final operation
// straight into the slot — `f(n - 1)` costs SUB alone instead of SUB into a temporary plus a
// MOVE, and a call still lands on its slot without one.
void Compiler::compile_consecutive(int base, const std::vector<std::unique_ptr<Expr>>& exprs, int count) {
    int n = count < 0 ? (int)exprs.size() : count;
    for (int i = 0; i < n; ++i)
        compile_into(*exprs[i], base + i, true);
}

void Compiler::visit(const ReturnStmt& s) {
    note_line(s.line, s.file_idx);
    if (!in_function())
        throw std::runtime_error(s.sloc().str(chunk.source_files) + ": return outside function");
    // Leaving the try blocks of THIS function pops their handlers, as a break does. Doing it here
    // and not in the VM is what keeps it free: popping them on every RETURN cost 1.23 % of the
    // instructions executed by bench_fib, measured, for a check that is useless without a try.
    for (int i = try_floor(); i < try_depth_; ++i)
        chunk.emit(make_bx((uint8_t)Op::POP_TRY, 0));
    // return <explicit values>, <call>: when the last returned expression is a call it expands
    // to ALL its values, as in Lua. `return ...` is still handled by spread_varargs.
    if (!s.spread_varargs && !s.values.empty() && is_call_node(s.values.back().get())) {
        int base = reg_top_;
        int n_expl = (int)s.values.size() - 1;
        compile_consecutive(base, s.values, n_expl);
        int want = base + n_expl;
        reg_top_ = want;
        s.values.back()->accept(*this); // a terminal call: k return values, hence last_results_ = k
        if (last_reg_ != want)
            chunk.emit(make_abc((uint8_t)Op::MOVE_RESULTS, (uint8_t)want, (uint8_t)last_reg_, 0));
        chunk.emit(make_abc((uint8_t)Op::RETURN_SPREAD, (uint8_t)base, (uint8_t)n_expl, 0));
        return;
    }
    if (s.spread_varargs) {
        int base = reg_top_;
        compile_consecutive(base, s.values);
        chunk.emit(make_abc((uint8_t)Op::RETURN_V, (uint8_t)base, (uint8_t)s.values.size(), 0));
    } else {
        int n = (int)s.values.size();
        if (n == 0) {
            chunk.emit(make_abc((uint8_t)Op::RETURN, 0, 0, 0));
        } else if (n == 1) {
            // RETURN A,1 copies R[A] into R[0], so ANY register will do: the value is compiled
            // where it falls, instead of being moved to the top of the scratch area first.
            s.values[0]->accept(*this);
            chunk.emit(make_abc((uint8_t)Op::RETURN, (uint8_t)last_reg_, 1, 0));
        } else {
            int base = reg_top_;
            compile_consecutive(base, s.values);
            chunk.emit(make_abc((uint8_t)Op::RETURN, (uint8_t)base, (uint8_t)n, 0));
        }
    }
}

void Compiler::visit(const NumberExpr& e) {
    last_reg_ = alloc_reg();
    chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_,
                        chunk.add_constant(e.is_integer ? Value(e.ival) : num_value(e.value))));
}

void Compiler::visit(const StringExpr& e) {
    last_reg_ = alloc_reg();
    chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_, chunk.add_constant(Value(e.value))));
}

void Compiler::visit(const InterpExpr& e) {
    note_line(e.line, e.file_idx);
    // Result is literals[0] + str(exprs[0]) + literals[1] + ... + literals[n]; an ADD with a
    // string on the left converts the right-hand side through value_to_string.
    // Accumulated IN PLACE: `ADD acc, acc, x` reads before it writes, as a compound assignment
    // does. Allocating a fresh register per piece burned three of them per placeholder, and a
    // string of some 85 pieces failed to compile on the 255-register limit.
    int acc = alloc_reg();
    chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)acc, (uint16_t)chunk.add_constant(Value(e.literals[0]))));
    int scratch = reg_top_; // the piece being appended, reused at every step
    for (int i = 0; i < (int)e.exprs.size(); ++i) {
        reg_top_ = scratch;
        e.exprs[i]->accept(*this);
        chunk.emit(make_abc((uint8_t)Op::ADD, (uint8_t)acc, (uint8_t)acc, (uint8_t)last_reg_));
        if (!e.literals[i + 1].empty()) {
            reg_top_ = scratch;
            int lit = alloc_reg();
            chunk.emit(
                make_abx((uint8_t)Op::LOAD_K, (uint8_t)lit, (uint16_t)chunk.add_constant(Value(e.literals[i + 1]))));
            chunk.emit(make_abc((uint8_t)Op::ADD, (uint8_t)acc, (uint8_t)acc, (uint8_t)lit));
        }
    }
    reg_top_ = scratch;
    last_reg_ = acc;
}

void Compiler::visit(const BoolExpr& e) {
    last_reg_ = alloc_reg();
    chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_, chunk.add_constant(Value::make_bool(e.value))));
}

void Compiler::visit(const NilExpr&) {
    last_reg_ = alloc_reg();
    chunk.emit(make_abc((uint8_t)Op::LOAD_NIL, (uint8_t)last_reg_, 0, 0));
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
    auto fit = func_table.find(e.name);
    if (fit != func_table.end()) {
        last_reg_ = alloc_reg();
        if (fit->second.is_closure) {
            chunk.emit(make_abx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)last_reg_, chunk.add_identifier(e.name)));
        } else {
            chunk.emit(make_abx((uint8_t)Op::LOAD_FUNC, (uint8_t)last_reg_, fit->second.func_idx));
        }
        return;
    }
    // Upvalue
    {
        int uv = resolve_upvalue(e.name);
        if (uv >= 0) {
            last_reg_ = alloc_reg();
            chunk.emit(make_abc((uint8_t)Op::GET_UPVAL, (uint8_t)last_reg_, (uint8_t)uv, 0));
            return;
        }
    }
    if (!declared_globals_.count(e.name))
        throw std::runtime_error(sloc().str(chunk.source_files) + ": undeclared variable '" + e.name + "'");
    last_reg_ = alloc_reg();
    chunk.emit(make_abx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)last_reg_, chunk.add_identifier(e.name)));
}

void Compiler::visit(const BinaryExpr& e) {
    // and (&) / or (|) short-circuit: the right side is evaluated only when needed, and the
    // result is a VALUE as in Lua — `a and b` is a when a is falsy, b otherwise; `a or b` is a
    // when a is truthy, b otherwise. The AND/OR opcodes remain in use for chained comparisons,
    // where both sides are already computed.
    if (e.op == '&' || e.op == '|') {
        // The left operand is compiled INTO dst: the value of the whole expression is the left
        // one whenever the short circuit fires, so copying it there afterwards was a MOVE per
        // evaluation.
        int dst = alloc_reg();
        compile_into(*e.left, dst);
        if (e.op == '&') {
            // a falsy: keep a, already in dst, and skip evaluating b
            size_t skip = chunk.emit_jump(Op::JUMP_IF_FALSE, (uint8_t)dst);
            e.right->accept(*this);
            chunk.emit(make_abc((uint8_t)Op::MOVE, (uint8_t)dst, (uint8_t)last_reg_, 0));
            chunk.patch_jump(skip, (uint16_t)chunk.current_pos());
        } else {
            // a truthy: keep a; a falsy: evaluate b
            size_t eval_right = chunk.emit_jump(Op::JUMP_IF_FALSE, (uint8_t)dst);
            size_t done = chunk.emit_jump(Op::JUMP);
            chunk.patch_jump(eval_right, (uint16_t)chunk.current_pos());
            e.right->accept(*this);
            chunk.emit(make_abc((uint8_t)Op::MOVE, (uint8_t)dst, (uint8_t)last_reg_, 0));
            chunk.patch_jump(done, (uint16_t)chunk.current_pos());
        }
        reg_top_ = dst + 1;
        last_reg_ = dst;
        return;
    }
    e.left->accept(*this);
    int r_l = last_reg_;
    // Protect the left result's register: a 0-argument call — or any expression leaving
    // reg_top_ <= r_l — would otherwise see the right operand overwrite it.
    if (reg_top_ <= r_l)
        reserve_regs_to(r_l + 1);
    e.right->accept(*this);
    int r_r = last_reg_;
    last_reg_ = reg_top_++;
    bump_reg_count();

    chunk.emit(make_abc((uint8_t)binary_arith_opcode(e.op), (uint8_t)last_reg_, (uint8_t)r_l, (uint8_t)r_r));
}

// a < b < c: each operand in its own register, comparisons taken pairwise, AND at the end.
void Compiler::visit(const ChainedCompareExpr& e) {
    int n = (int)e.operands.size(); // n operands, n-1 operators

    // Evaluate every operand into contiguous temporaries.
    int base_tmp = reg_top_;
    std::vector<int> regs;
    for (int i = 0; i < n; i++) {
        e.operands[i]->accept(*this);
        regs.push_back(last_reg_);
        if (last_reg_ >= reg_top_) {
            reserve_regs_to(last_reg_ + 1);
        }
    }

    // Allocate n-1 registers for the comparison results.
    int cmp_base = reg_top_;
    reserve_regs_to(reg_top_ + n - 1);

    for (int i = 0; i < n - 1; i++)
        chunk.emit(make_abc((uint8_t)binary_arith_opcode(e.ops[i]), (uint8_t)(cmp_base + i), (uint8_t)regs[i],
                            (uint8_t)regs[i + 1]));

    // Fold the partial results together with AND, into cmp_base.
    for (int i = 1; i < n - 1; i++)
        chunk.emit(make_abc((uint8_t)Op::AND, (uint8_t)cmp_base, (uint8_t)cmp_base, (uint8_t)(cmp_base + i)));

    last_reg_ = cmp_base;
    reg_top_ = base_tmp; // frees every temporary after the expression
}

void Compiler::visit(const UnaryExpr& e) {
    Value folded;
    if (negated_literal(e, folded)) {
        last_reg_ = alloc_reg();
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_, chunk.add_constant(folded)));
        return;
    }
    e.operand->accept(*this);
    int r_in = last_reg_;
    last_reg_ = alloc_reg();
    chunk.emit(make_abc((uint8_t)unary_opcode(e.op), (uint8_t)last_reg_, (uint8_t)r_in, 0));
}

void Compiler::emit_callee_value(const std::string& name, int reg) {
    auto rit = local_regs_.find(name);
    if (rit != local_regs_.end()) {
        if (rit->second != reg)
            chunk.emit(make_abc((uint8_t)Op::MOVE, (uint8_t)reg, (uint8_t)rit->second, 0));
        return;
    }
    int uv = resolve_upvalue(name);
    if (uv >= 0) {
        chunk.emit(make_abc((uint8_t)Op::GET_UPVAL, (uint8_t)reg, (uint8_t)uv, 0));
        return;
    }
    // Builtins and top-level functions, closures included, are globals (STORE_GLOBAL).
    chunk.emit(make_abx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)reg, chunk.add_identifier(name)));
}

void Compiler::emit_spread_call(const std::vector<std::unique_ptr<Expr>>& args,
                                const std::function<void(int)>& emit_callee) {
    int n_fixed = (int)args.size() - 1;
    const Expr* last = args.back().get();
    bool is_vararg = dynamic_cast<const VarArgExpr*>(last) != nullptr;

    int func_slot = reg_top_++; // the callee sits BELOW the argument block, so an expansion never overwrites it
    bump_reg_count();
    int call_base = reg_top_;
    for (int i = 0; i < n_fixed; ++i) {
        int target = call_base + i;
        reg_top_ = target;
        args[i]->accept(*this);
        if (last_reg_ != target)
            chunk.emit(make_abc((uint8_t)Op::MOVE, (uint8_t)target, (uint8_t)last_reg_, 0));
        reserve_regs_to(target + 1);
    }
    emit_callee(func_slot);
    if (is_vararg) {
        chunk.emit(make_abc((uint8_t)Op::CALL_VARARGS, (uint8_t)call_base, (uint8_t)func_slot, (uint8_t)n_fixed));
    } else {
        // The last argument is a call: its k return values must sit contiguously after the fixed
        // ones, at call_base+n_fixed. last_results_ is k at runtime, hence CALL_VA with
        // argc = n_fixed + k.
        int want = call_base + n_fixed;
        reg_top_ = want;
        args.back()->accept(*this);
        if (last_reg_ != want) // the nested call spread as well, so recompose at `want`
            chunk.emit(make_abc((uint8_t)Op::MOVE_RESULTS, (uint8_t)want, (uint8_t)last_reg_, 0));
        chunk.emit(make_abc((uint8_t)Op::CALL_VA, (uint8_t)call_base, (uint8_t)func_slot, (uint8_t)n_fixed));
    }
    last_reg_ = call_base;
    reserve_regs_to(call_base + 1);
}

void Compiler::emit_optional_call(const std::vector<std::unique_ptr<Expr>>& args,
                                  const std::function<void(int)>& emit_callee) {
    int call_base = reg_top_;
    int argc = (int)args.size();
    int func_reg = call_base + argc;
    reg_top_ = call_base + 1;
    emit_callee(call_base); // call_base holds the callee: both the test and the result slot
    reserve_regs_to(func_reg + 1);
    // f?(args) is `if f then f(args) else nil`: JUMP_IF_FALSE (nil being falsy) jumps over the
    // arguments, which are therefore NOT evaluated when f is falsy.
    size_t to_nil = chunk.emit_jump(Op::JUMP_IF_FALSE, (uint8_t)call_base);
    chunk.emit(make_abc((uint8_t)Op::MOVE, (uint8_t)func_reg, (uint8_t)call_base, 0));
    for (int i = 0; i < argc; ++i) { // temporaries above func_reg
        reg_top_ = func_reg + 1;
        compile_into(*args[i], call_base + i);
    }
    reserve_regs_to(func_reg + 1);
    chunk.emit(make_abc((uint8_t)Op::CALL_DYN, (uint8_t)call_base, (uint8_t)func_reg, (uint8_t)argc));
    size_t to_end = chunk.emit_jump(Op::JUMP);
    chunk.patch_jump(to_nil, (uint16_t)chunk.current_pos());
    chunk.emit(make_abc((uint8_t)Op::LOAD_NIL, (uint8_t)call_base, 0, 0));
    chunk.patch_jump(to_end, (uint16_t)chunk.current_pos());
    reg_top_ = call_base + 1;
    last_reg_ = call_base;
}

void Compiler::visit(const CallExpr& e) {
    // A multi-value last argument (`...` or a call) EXPANDS, an optional call excepted.
    if (!e.optional && !e.args.empty() && is_multi_value_expr(e.args.back().get())) {
        emit_spread_call(e.args, [&](int reg) { emit_callee_value(e.callee, reg); });
        return;
    }
    if (e.optional) {
        emit_optional_call(e.args, [&](int reg) { emit_callee_value(e.callee, reg); });
        return;
    }

    // A local, a parameter or an upvalue SHADOWS a top-level function of the same name — exactly
    // as it does when the name is read as a VALUE (visit(VarExpr)). Consulting func_table first
    // made `func run(handler) return handler() end` call the global `handler` instead of its own
    // parameter, so `print(f)` and `f()` named two different things in one scope.
    // resolve_upvalue only creates the upvalue when it finds one, and it caches, so testing here
    // costs nothing and adds nothing to the proto.
    bool shadowed = local_regs_.count(e.callee) != 0 || resolve_upvalue(e.callee) >= 0;
    auto it = shadowed ? func_table.end() : func_table.find(e.callee);
    if (it != func_table.end()) {
        int call_base = reg_top_;
        int argc = (int)e.args.size();
        compile_consecutive(call_base, e.args);
        if (it->second.is_closure) {
            int func_reg = alloc_reg();
            chunk.emit(make_abx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)func_reg, chunk.add_identifier(e.callee)));
            chunk.emit(make_abc((uint8_t)Op::CALL_DYN, (uint8_t)call_base, (uint8_t)func_reg, (uint8_t)argc));
        } else {
            chunk.emit(make_abc((uint8_t)Op::CALL_FUNC, (uint8_t)call_base, it->second.func_idx, (uint8_t)argc));
        }
        last_reg_ = call_base;
        return;
    }

    // Builtins
    int call_base = reg_top_;
    int argc = (int)e.args.size();
    compile_consecutive(call_base, e.args);

    // Every call goes through CALL_DYN; builtins are T_BUILTIN globals.
    {
        int func_reg = alloc_reg();
        {
            auto rit = local_regs_.find(e.callee);
            if (rit != local_regs_.end()) {
                func_reg = rit->second;
                reg_top_--;
            } else {
                int uv = resolve_upvalue(e.callee);
                if (uv >= 0) {
                    chunk.emit(make_abc((uint8_t)Op::GET_UPVAL, (uint8_t)func_reg, (uint8_t)uv, 0));
                } else {
                    chunk.emit(make_abx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)func_reg, chunk.add_identifier(e.callee)));
                }
            }
        }
        chunk.emit(make_abc((uint8_t)Op::CALL_DYN, (uint8_t)call_base, (uint8_t)func_reg, (uint8_t)argc));
        last_reg_ = call_base;
    }
}

void Compiler::visit(const ExprCallExpr& e) {
    // A multi-value last argument (`...` or a call) EXPANDS, an optional call excepted.
    if (!e.optional && !e.args.empty() && is_multi_value_expr(e.args.back().get())) {
        emit_spread_call(e.args, [&](int reg) { compile_into(*e.callee, reg); });
        return;
    }
    int call_base = reg_top_;
    int argc = (int)e.args.size();

    if (e.optional) {
        emit_optional_call(e.args, [&](int reg) { compile_into(*e.callee, reg); });
        return;
    }

    // Compile args into consecutive registers
    compile_consecutive(call_base, e.args);

    // Compile callee into a temp register after args
    int func_reg = alloc_reg();
    compile_into(*e.callee, func_reg);

    chunk.emit(make_abc((uint8_t)Op::CALL_DYN, (uint8_t)call_base, (uint8_t)func_reg, (uint8_t)argc));
    last_reg_ = call_base;
}

void Compiler::visit(const VarArgExpr&) {
    if (!in_function())
        throw std::runtime_error(sloc().str(chunk.source_files) + ": ... outside a variadic function");
    // A SINGLE value by default (the first vararg, or nil when there is none): count=1, padded
    // with nil. Multi-value consumers — a call, an array, a return, a trailing destructuring —
    // emit LOAD_VARARGS with count=0 themselves for the full expansion.
    int base = reg_top_;
    chunk.emit(make_abc((uint8_t)Op::LOAD_VARARGS, (uint8_t)base, 1, 0));
    last_reg_ = base;
}

void Compiler::visit(const MapExpr& e) {
    int dest = alloc_reg();
    chunk.emit(make_abc((uint8_t)Op::NEW_MAP, (uint8_t)dest, 0, 0));
    for (auto& entry : e.entries) {
        int saved = reg_top_;
        int key_reg = alloc_reg();
        compile_into(*entry.key, key_reg); // a literal StringExpr OR a computed key
        int val_reg = alloc_reg();
        compile_into(*entry.value, val_reg);
        chunk.emit(make_abc((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_reg, (uint8_t)val_reg));
        reg_top_ = saved;
    }
    last_reg_ = dest;
}

void Compiler::visit(const IndexExpr& e) {
    e.obj->accept(*this);
    int obj_r = last_reg_;
    // Reserve the object's register before evaluating the key: a 0-argument call leaves
    // reg_top_ at its own result register, so without this guard evaluating the key would
    // reallocate over the object (same as in BinaryExpr). See f().x and f()[i].
    if (reg_top_ <= obj_r)
        reserve_regs_to(obj_r + 1);
    int saved2 = reg_top_;
    e.key->accept(*this);
    int key_r = last_reg_;
    reg_top_ = saved2;
    int dest = alloc_reg();
    chunk.emit(make_abc((uint8_t)Op::GET_INDEX, (uint8_t)dest, (uint8_t)obj_r, (uint8_t)key_r));
    last_reg_ = dest;
}

void Compiler::visit(const ArrayExpr& e) {
    int dest = alloc_reg();
    chunk.emit(make_abc((uint8_t)Op::NEW_ARRAY, (uint8_t)dest, 0, 0));
    int n = (int)e.elements.size();
    for (int i = 0; i < n; ++i) {
        const Expr* elem = e.elements[i].get();
        bool last_pos = (i == n - 1);
        // In LAST position a multi-value element expands, as in Lua: `...` to every vararg, a
        // call to all of its return values.
        if (last_pos && dynamic_cast<const VarArgExpr*>(elem)) {
            chunk.emit(make_abc((uint8_t)Op::ARRAY_PUSH_VARARGS, (uint8_t)dest, 0, 0));
        } else if (last_pos && is_call_node(elem)) {
            int saved = reg_top_;
            int spread_base = reg_top_;
            e.elements[i]->accept(*this); // k values at spread_base.., with last_results_ = k
            chunk.emit(make_abc((uint8_t)Op::ARRAY_PUSH_SPREAD, (uint8_t)dest, (uint8_t)spread_base, 0));
            reg_top_ = saved;
        } else {
            int saved = reg_top_;
            int val_r = alloc_reg();
            compile_into(*e.elements[i], val_r);
            chunk.emit(make_abc((uint8_t)Op::ARRAY_PUSH, (uint8_t)dest, (uint8_t)val_r, 0));
            reg_top_ = saved;
        }
    }
    last_reg_ = dest;
}

void Compiler::visit(const RangeExpr& e) {
    // Allocate dest first, then use temps above it
    int dest = alloc_reg(); // dest = reg_top_-1

    // Temps: base = dest+1 for start, base+1 for end, base+2 for step
    int base = reg_top_; // = dest+1

    // Compile start
    int start_r = base;
    reserve_regs_to(base + 1);
    compile_into(*e.start, start_r);

    // Compile end
    int end_r = base + 1;
    reserve_regs_to(base + 2);
    compile_into(*e.end, end_r);

    // Compile step if present
    bool has_step = (e.step != nullptr);
    if (has_step) {
        int step_r = base + 2;
        reserve_regs_to(base + 3);
        compile_into(*e.step, step_r);
    }

    // If open-left: adjust start = start + step_or_1
    if (!e.incl_left) {
        if (has_step) {
            chunk.emit(make_abc((uint8_t)Op::ADD, (uint8_t)start_r, (uint8_t)start_r, (uint8_t)(base + 2)));
        } else {
            int one_r = base + 2;
            reserve_regs_to(base + 3);
            chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)one_r, chunk.add_constant(Value((int64_t)1))));
            chunk.emit(make_abc((uint8_t)Op::ADD, (uint8_t)start_r, (uint8_t)start_r, (uint8_t)one_r));
        }
    }

    // Build flags: bit0 = incl_right, bit1 = has_step
    uint8_t flags = (uint8_t)((has_step ? 2 : 0) | (e.incl_right ? 1 : 0));

    chunk.emit(make_abc((uint8_t)Op::MAKE_RANGE, (uint8_t)dest, (uint8_t)base, flags));

    // Restore reg_top_ to dest+1 (temps freed, dest still "live")
    reg_top_ = dest + 1;
    last_reg_ = dest;
}

void Compiler::compile_iterator_loop(const Expr& src, const std::string& var1, const std::string& var2,
                                     const std::vector<std::unique_ptr<Stmt>>& body) {
    bool two_vars = !var2.empty();
    int block = reg_top_;
    int tmp_src = block + (two_vars ? 3 : 2);
    reserve_regs_to(tmp_src + 1);

    compile_into(src, tmp_src); // src is compiled BEFORE the loop variables are scoped
    chunk.emit(make_abc((uint8_t)Op::MAKE_ITER, (uint8_t)block, (uint8_t)tmp_src, 0));
    reg_top_ = tmp_src;

    // The loop variables are scoped by aliasing them onto the registers FOR_ITER_NEXT writes
    // (block+1 is the key or primary, block+2 the value). No copy is made: the value is rewritten
    // every turn, so assigning to the variable inside the body has no effect. The bindings are
    // saved and restored, so nothing leaks past the loop.
    auto save_bind = [&](const std::string& n, int reg, bool& had, int& old) {
        auto it = local_regs_.find(n);
        had = (it != local_regs_.end());
        old = had ? it->second : -1;
        local_regs_[n] = reg;
    };
    auto restore_bind = [&](const std::string& n, bool had, int old) {
        if (had)
            local_regs_[n] = old;
        else
            local_regs_.erase(n);
    };
    bool had1, had2 = false;
    int old1, old2 = -1;
    save_bind(var1, block + 1, had1, old1);
    if (two_vars)
        save_bind(var2, block + 2, had2, old2);

    auto loop_start = (uint16_t)chunk.current_pos();
    Op iter_op = two_vars ? Op::FOR_ITER_NEXT : Op::FOR_ITER_NEXT1;
    size_t exit_patch = chunk.emit_jump(iter_op, (uint8_t)block);

    break_patches.push_back({{}, outer_scopes_.size(), try_depth_, false});
    continue_patches.push_back({{}, outer_scopes_.size(), try_depth_, false});
    compile_block(body);
    // End of an iteration: the loop variables and the body's locals go out of scope, so their
    // upvalues are closed and the next turn creates fresh ones — one variable per iteration.
    // `continue` jumps HERE, so it goes through the same closing.
    bool close_scope = body_carries_func(body);
    uint16_t iter_end = (uint16_t)chunk.current_pos();
    if (close_scope)
        chunk.emit(make_abc((uint8_t)Op::CLOSE_UPVALS, (uint8_t)(block + 1), 0, 0));
    for (size_t p : continue_patches.back().patches)
        chunk.patch_jump(p, iter_end);
    continue_patches.pop_back();
    chunk.emit(make_bx((uint8_t)Op::JUMP, loop_start));

    uint16_t exit = (uint16_t)chunk.current_pos();
    // Exit (normal end, exhausted iterator, or `break`): the same closing, so that the last
    // iteration behaves like the others.
    if (close_scope)
        chunk.emit(make_abc((uint8_t)Op::CLOSE_UPVALS, (uint8_t)(block + 1), 0, 0));
    chunk.patch_jump(exit_patch, exit);
    for (size_t p : break_patches.back().patches)
        chunk.patch_jump(p, exit);
    break_patches.pop_back();

    restore_bind(var1, had1, old1);
    if (two_vars)
        restore_bind(var2, had2, old2);
    reg_top_ = keep_captured_regs(body, block + (two_vars ? 3 : 2), block, reg_top_);
}

void Compiler::visit(const ForIterStmt& s) {
    note_line(s.line, s.file_idx);
    // Fast path: `for i in <range literal, inclusive on both bounds>` with one variable, which
    // covers the `for i = a, b[, step]` form. It avoids the Range object, the iterator and the
    // virtual dispatch.
    if (s.var2.empty()) {
        if (auto* r = dynamic_cast<const RangeExpr*>(s.iter_expr.get())) {
            if (r->incl_left && r->incl_right) {
                compile_numeric_for(*r, s.var1, s.body);
                return;
            }
        }
    }
    compile_iterator_loop(*s.iter_expr, s.var1, s.var2, s.body);
}

// True when the expression contains a lambda, which could capture the loop variable.
static bool expr_has_lambda(const Expr* e) {
    if (!e)
        return false;
    if (dynamic_cast<const FuncExpr*>(e))
        return true;
    if (auto* b = dynamic_cast<const BinaryExpr*>(e))
        return expr_has_lambda(b->left.get()) || expr_has_lambda(b->right.get());
    if (auto* u = dynamic_cast<const UnaryExpr*>(e))
        return expr_has_lambda(u->operand.get());
    if (auto* c = dynamic_cast<const CallExpr*>(e)) {
        for (auto& a : c->args)
            if (expr_has_lambda(a.get()))
                return true;
        return false;
    }
    if (auto* c = dynamic_cast<const ExprCallExpr*>(e)) {
        if (expr_has_lambda(c->callee.get()))
            return true;
        for (auto& a : c->args)
            if (expr_has_lambda(a.get()))
                return true;
        return false;
    }
    if (auto* m = dynamic_cast<const MethodCallExpr*>(e)) {
        if (expr_has_lambda(m->receiver.get()))
            return true;
        for (auto& a : m->args)
            if (expr_has_lambda(a.get()))
                return true;
        return false;
    }
    if (auto* i = dynamic_cast<const IndexExpr*>(e))
        return expr_has_lambda(i->obj.get()) || expr_has_lambda(i->key.get());
    if (auto* mp = dynamic_cast<const MapExpr*>(e)) {
        for (auto& en : mp->entries)
            if (expr_has_lambda(en.key.get()) || expr_has_lambda(en.value.get()))
                return true;
        return false;
    }
    if (auto* ar = dynamic_cast<const ArrayExpr*>(e)) {
        for (auto& x : ar->elements)
            if (expr_has_lambda(x.get()))
                return true;
        return false;
    }
    if (auto* rg = dynamic_cast<const RangeExpr*>(e))
        return expr_has_lambda(rg->start.get()) || expr_has_lambda(rg->end.get()) || expr_has_lambda(rg->step.get());
    if (auto* cc = dynamic_cast<const ChainedCompareExpr*>(e)) {
        for (auto& o : cc->operands)
            if (expr_has_lambda(o.get()))
                return true;
        return false;
    }
    if (dynamic_cast<const VarExpr*>(e) || dynamic_cast<const NumberExpr*>(e) || dynamic_cast<const StringExpr*>(e) ||
        dynamic_cast<const BoolExpr*>(e) || dynamic_cast<const NilExpr*>(e) || dynamic_cast<const VarArgExpr*>(e))
        return false;
    return true; // an unknown type, hence the conservative answer
}

// True when the body is safe for aliasing the loop variable 'v' onto the control register: no
// assignment to v, no lambda, no nested control structure. Deliberately conservative, so it
// covers leaf bodies such as s += i.
static bool loop_body_alias_safe(const std::vector<std::unique_ptr<Stmt>>& body, const std::string& v) {
    for (auto& sp : body) {
        const Stmt* s = sp.get();
        if (auto* a = dynamic_cast<const AssignStmt*>(s)) {
            if (a->name == v)
                return false;
            if (expr_has_lambda(a->value.get()))
                return false;
        } else if (auto* m = dynamic_cast<const MultiAssignStmt*>(s)) {
            for (auto& t : m->targets) {
                if (t.kind == LValue::VAR && t.name == v)
                    return false;
                if (t.key && expr_has_lambda(t.key.get()))
                    return false;
            }
            for (auto& val : m->values)
                if (expr_has_lambda(val.get()))
                    return false;
        } else if (auto* d = dynamic_cast<const VarDeclStmt*>(s)) {
            for (auto& n : d->names)
                if (n == v)
                    return false; // shadow
            for (auto& val : d->values)
                if (expr_has_lambda(val.get()))
                    return false;
        } else if (auto* e = dynamic_cast<const ExprStmt*>(s)) {
            if (expr_has_lambda(e->expr.get()))
                return false;
        } else if (auto* r = dynamic_cast<const ReturnStmt*>(s)) {
            for (auto& x : r->values)
                if (expr_has_lambda(x.get()))
                    return false;
        } else if (auto* th = dynamic_cast<const ThrowStmt*>(s)) {
            if (expr_has_lambda(th->value.get()))
                return false;
        } else if (auto* ia = dynamic_cast<const IndexAssignStmt*>(s)) {
            // obj == v does not write v, it writes into its container; check the key, the value
            // and the chained container (obj_expr) if there is one.
            if (expr_has_lambda(ia->key.get()) || expr_has_lambda(ia->value.get()) ||
                (ia->obj_expr && expr_has_lambda(ia->obj_expr.get())))
                return false;
        } else if (dynamic_cast<const BreakStmt*>(s) || dynamic_cast<const ContinueStmt*>(s) ||
                   dynamic_cast<const CommentStmt*>(s)) {
            // safe
        } else {
            return false; // if/while/for/block/try/switch/funcdecl/…: stay conservative
        }
    }
    return true;
}

// True when the body contains a function or closure anywhere, recursively. It decides whether
// the loop registers can be recycled on exit: a closure may capture the loop variable's register
// through an open upvalue,
// in which case the register stays reserved so nothing overwrites it after the loop.
static bool body_has_func(const std::vector<std::unique_ptr<Stmt>>& body);
// Does this node CARRY a function directly — a declaration, or a lambda in one of its own
// expressions? DESCENDING into the sub-bodies is stmt_has_func's job, through
// Stmt::for_each_body, so no list of composite kinds is maintained here. Such a list is exactly
// what had left `do ... end` out, with a closure reading a recycled register.
struct HasFuncQuery : StmtQuery {
    bool result = false;
    void visit(const FuncDeclStmt&) override {
        result = true;
    }
    // A class CARRIES its methods, which are functions and can capture a variable of the
    // enclosing block through an upvalue — verified: a method declared inside a loop does read
    // the loop variable. So "yes" is the EXACT answer here, not a fallback.
    void visit(const ClassDeclStmt&) override {
        result = true;
    }
    // Switch and enum answer "yes" without looking at their expressions. That is a fallback,
    // and it is KEPT: refining it unlocks no optimization, because loop_body_alias_safe already
    // refuses to alias the loop variable as soon as a structure is nested. body_has_func only
    // drives reg_top_, hence the number of reserved registers — measured on a 10M loop
    // containing a switch: no gain at all (+0.9 %, below the code-layout noise). Do not refine
    // it again without a new measurement.
    void visit(const SwitchStmt&) override {
        result = true;
    }
    void visit(const EnumDeclStmt&) override {
        result = true;
    }
    void visit(const AssignStmt& s) override {
        result = expr_has_lambda(s.value.get());
    }
    void visit(const ExprStmt& s) override {
        result = expr_has_lambda(s.expr.get());
    }
    void visit(const ThrowStmt& s) override {
        result = expr_has_lambda(s.value.get());
    }
    void visit(const IndexAssignStmt& s) override {
        result = expr_has_lambda(s.key.get()) || expr_has_lambda(s.value.get()) ||
                 (s.obj_expr && expr_has_lambda(s.obj_expr.get()));
    }
    void visit(const MultiAssignStmt& s) override {
        for (auto& v : s.values)
            if (expr_has_lambda(v.get())) {
                result = true;
                return;
            }
        for (auto& t : s.targets)
            if (t.key && expr_has_lambda(t.key.get())) {
                result = true;
                return;
            }
    }
    void visit(const VarDeclStmt& s) override {
        for (auto& v : s.values)
            if (expr_has_lambda(v.get())) {
                result = true;
                return;
            }
    }
    void visit(const ReturnStmt& s) override {
        for (auto& v : s.values)
            if (expr_has_lambda(v.get())) {
                result = true;
                return;
            }
    }
    // Nodes with bodies: only their OWN expressions are examined here.
    void visit(const WhileStmt& s) override {
        result = expr_has_lambda(s.cond.get());
    }
    void visit(const ForIterStmt& s) override {
        result = expr_has_lambda(s.iter_expr.get());
    }
    void visit(const IfStmt& s) override {
        if (expr_has_lambda(s.cond.get())) {
            result = true;
            return;
        }
        for (auto& ei : s.else_ifs)
            if (expr_has_lambda(ei.cond.get())) {
                result = true;
                return;
            }
    }
    // TryCatchStmt, BlockStmt and DoStmt have no expressions of their own, so descending is
    // enough; BreakStmt, ContinueStmt and CommentStmt have nothing either.
};
static bool stmt_has_func(const Stmt* s) {
    HasFuncQuery q;
    s->accept(q);
    if (q.result)
        return true;
    bool found = false;
    s->for_each_body([&found](const std::vector<std::unique_ptr<Stmt>>& sub) {
        if (!found)
            found = body_has_func(sub);
    });
    return found;
}
static bool body_has_func(const std::vector<std::unique_ptr<Stmt>>& body) {
    for (auto& s : body)
        if (stmt_has_func(s.get()))
            return true;
    return false;
}

void Compiler::compile_numeric_for(const RangeExpr& r, const std::string& var1,
                                   const std::vector<std::unique_ptr<Stmt>>& body) {
    int ctl = reg_top_; // ctl, ctl+1, ctl+2 = i, limit, step
    reserve_regs_to(ctl + 3);

    // Bounds are compiled BEFORE i is scoped, so that `for i = i, …` reads the outer i.
    compile_into(*r.start, ctl);
    compile_into(*r.end, ctl + 1);
    if (r.step)
        compile_into(*r.step, ctl + 2);
    else
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)(ctl + 2), chunk.add_constant(Value((int64_t)1))));
    reg_top_ = ctl + 3;

    // The loop variable is scoped. When the body never writes i it is aliased onto ctl, with no
    // copy; otherwise it gets its own register and a copy each turn, so the body can modify i
    // without touching the counter — an assignment with no effect. The binding is restored on
    // exit, so nothing leaks past the loop.
    bool can_alias = loop_body_alias_safe(body, var1);
    int var_reg = ctl;
    if (!can_alias) {
        var_reg = reg_top_++;
        bump_reg_count();
    }
    bool had_old;
    int old_reg;
    {
        auto it = local_regs_.find(var1);
        had_old = (it != local_regs_.end());
        old_reg = had_old ? it->second : -1;
    }
    local_regs_[var1] = var_reg;

    size_t prep = chunk.emit_jump(Op::FOR_PREP, (uint8_t)ctl); // Bx is the exit for an empty loop, patched later

    uint16_t body_addr = (uint16_t)chunk.current_pos(); // FOR_PREP falls through to here when the loop is not empty
    if (!can_alias)
        chunk.emit(make_abc((uint8_t)Op::MOVE, (uint8_t)var_reg, (uint8_t)ctl, 0));

    break_patches.push_back({{}, outer_scopes_.size(), try_depth_, false});
    continue_patches.push_back({{}, outer_scopes_.size(), try_depth_, false});
    compile_block(body);

    // End of an iteration: close the upvalues of the body's scope, as in the iterator loop.
    // Closing does not modify the registers, so FOR_LOOP finds its counter intact.
    bool close_scope = body_carries_func(body);
    uint16_t loop_addr = (uint16_t)chunk.current_pos();
    if (close_scope)
        chunk.emit(make_abc((uint8_t)Op::CLOSE_UPVALS, (uint8_t)var_reg, 0, 0));
    for (size_t p : continue_patches.back().patches)
        chunk.patch_jump(p, loop_addr);
    continue_patches.pop_back();
    chunk.emit(make_abx((uint8_t)Op::FOR_LOOP, (uint8_t)ctl, body_addr));

    uint16_t exit_addr = (uint16_t)chunk.current_pos();
    if (close_scope)
        chunk.emit(make_abc((uint8_t)Op::CLOSE_UPVALS, (uint8_t)var_reg, 0, 0));
    chunk.patch_jump(prep, exit_addr); // FOR_PREP jumps here when the loop is empty
    for (size_t p : break_patches.back().patches)
        chunk.patch_jump(p, exit_addr);
    break_patches.pop_back();

    if (had_old)
        local_regs_[var1] = old_reg;
    else
        local_regs_.erase(var1); // restore the scope
    // Register recycling: when a closure in the body captures i we keep its register reserved,
    // otherwise it would be overwritten after the loop and the upvalue would be corrupted.
    // Do NOT drop below what compile_block reserved for the body's LOCALS, which a closure can
    // capture too: handing those back as temporaries overwrote their value under an upvalue that
    // was still open.
    reg_top_ = keep_captured_regs(body, var_reg + 1, ctl, reg_top_);
}

// A visible write to an enum is refused at compile time, which lets the message name both the
// enumeration and the element. The VM still catches the indirect paths (an alias, a computed key)
// with a generic message. A local of the same name shadows the enum.
void Compiler::reject_enum_write(const std::string& obj_name, const Expr* obj_expr, const std::string& field, int line,
                                 int file_idx) {
    if (enum_names_.empty())
        return; // no enum in the program, so nothing to check
    const std::string* name = &obj_name;
    if (obj_expr) {
        auto* ve = dynamic_cast<const VarExpr*>(obj_expr);
        if (!ve)
            return; // a chained target (a.b[k]): the object written is not the enum itself
        name = &ve->name;
    }
    if (!enum_names_.count(*name) || local_regs_.count(*name))
        return;
    throw std::runtime_error(where(line, file_idx) + ": cannot modify enum '" + *name + "'" +
                             (field.empty() ? "" : " element '" + field + "'"));
}

void Compiler::visit(const IndexAssignStmt& s) {
    note_line(s.line, s.file_idx);
    int saved = reg_top_;

    {
        auto* key_lit = dynamic_cast<const StringExpr*>(s.key.get());
        reject_enum_write(s.obj, s.obj_expr.get(), key_lit ? key_lit->value : std::string(), s.line, s.file_idx);
    }

    // Load the container (map or array) to index.
    int obj_r;
    if (s.obj_expr) {
        // Chained target (a.b.c, a[i][j]…): the container is an expression, evaluated into a
        // register. Maps and arrays being ref-counted, the SET_INDEX that follows does mutate the
        // original object.
        obj_r = alloc_reg();
        compile_into(*s.obj_expr, obj_r);
    } else {
        auto it = local_regs_.find(s.obj);
        if (it != local_regs_.end()) {
            obj_r = it->second;
        } else {
            int uv = resolve_upvalue(s.obj);
            obj_r = alloc_reg();
            if (uv >= 0) {
                chunk.emit(make_abc((uint8_t)Op::GET_UPVAL, (uint8_t)obj_r, (uint8_t)uv, 0));
            } else {
                if (!declared_globals_.count(s.obj))
                    throw std::runtime_error(where(s) + ": undeclared variable '" + s.obj + "'");
                chunk.emit(make_abx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)obj_r, chunk.add_identifier(s.obj)));
            }
        }
    }

    // Compile key
    int key_r = alloc_reg();
    compile_into(*s.key, key_r);

    if (s.op == TokenType::EQUALS) {
        // Simple assignment: SET_INDEX obj_r, key_r, val_r
        int val_r = alloc_reg();
        compile_into(*s.value, val_r);
        chunk.emit(make_abc((uint8_t)Op::SET_INDEX, (uint8_t)obj_r, (uint8_t)key_r, (uint8_t)val_r));
    } else {
        // Compound assignment: get current, apply op, store back
        int cur_r = alloc_reg();
        chunk.emit(make_abc((uint8_t)Op::GET_INDEX, (uint8_t)cur_r, (uint8_t)obj_r, (uint8_t)key_r));
        int rhs_r = alloc_reg();
        compile_into(*s.value, rhs_r);
        int result_r = alloc_reg();
        bump_reg_count();
        chunk.emit(make_abc((uint8_t)token_to_op(s.op), (uint8_t)result_r, (uint8_t)cur_r, (uint8_t)rhs_r));
        chunk.emit(make_abc((uint8_t)Op::SET_INDEX, (uint8_t)obj_r, (uint8_t)key_r, (uint8_t)result_r));
    }
    reg_top_ = saved;
}

void Compiler::visit(const MultiAssignStmt& s) {
    note_line(s.line, s.file_idx);
    int saved = reg_top_;

    // Evaluate every right-hand side into consecutive temporaries.
    int base = reg_top_;
    int n = (int)s.values.size();
    int n_targets = (int)s.targets.size();
    // Multi-return, taking the SAME path as `var a, b = f()` (visit(VarDeclStmt)): the VM leaves
    // the k return values from `base` on, and SPREAD_RESULTS nils the targets beyond k. Without
    // this path only one value was counted, so the later targets read neighbouring temporaries
    // and the values came out SHIFTED — `a, b, c = f()` gave 1, 1, 2 for a 1, 2, 3 return.
    if (n_targets > 1 && n == 1 && is_multi_value_expr(s.values[0].get())) {
        if (dynamic_cast<const VarArgExpr*>(s.values[0].get())) {
            chunk.emit(make_abc((uint8_t)Op::LOAD_VARARGS, (uint8_t)base, (uint8_t)n_targets, 0));
        } else {
            s.values[0]->accept(*this);
            if (last_reg_ != base)
                chunk.emit(make_abc((uint8_t)Op::MOVE_RESULTS, (uint8_t)base, (uint8_t)last_reg_, 0));
        }
        if (base + n_targets > reg_count_)
            reg_count_ = base + n_targets;
        chunk.emit(make_abc((uint8_t)Op::SPREAD_RESULTS, (uint8_t)base, (uint8_t)n_targets, 0));
        reg_top_ = base + n_targets;
        n = n_targets; // each target now has its value at base+i
    } else {
        for (int i = 0; i < n; ++i) {
            int r = alloc_reg();
            compile_into(*s.values[i], r);
        }
    }

    // Assign each target from its temporary, or nil when there are fewer values than targets.
    for (int i = 0; i < n_targets; ++i) {
        int val_r = (i < n) ? base + i : alloc_reg(); // nil when there is no value
        const LValue& lv = s.targets[i];
        // FIELD_INDEX (a.b[k]) writes into a.b, not into a, so the refusal does not apply.
        if (lv.kind == LValue::FIELD || lv.kind == LValue::INDEX)
            reject_enum_write(lv.name, nullptr, lv.kind == LValue::FIELD ? lv.field : std::string(), s.line,
                              s.file_idx);

        if (lv.kind == LValue::VAR) {
            auto it = local_regs_.find(lv.name);
            if (it != local_regs_.end()) {
                if (val_r != it->second)
                    chunk.emit(make_abc((uint8_t)Op::MOVE, (uint8_t)it->second, (uint8_t)val_r, 0));
            } else {
                int uv = resolve_upvalue(lv.name);
                if (uv >= 0) {
                    chunk.emit(make_abc((uint8_t)Op::SET_UPVAL, (uint8_t)val_r, (uint8_t)uv, 0));
                } else {
                    chunk.emit(make_abx((uint8_t)Op::STORE_GLOBAL, (uint8_t)val_r, chunk.add_identifier(lv.name)));
                }
            }
        } else {
            // FIELD or INDEX: load the object.
            int obj_r = alloc_reg();
            auto it = local_regs_.find(lv.name);
            if (it != local_regs_.end()) {
                obj_r = it->second;
                reg_top_--;
            } else {
                int uv = resolve_upvalue(lv.name);
                if (uv >= 0)
                    chunk.emit(make_abc((uint8_t)Op::GET_UPVAL, (uint8_t)obj_r, (uint8_t)uv, 0));
                else
                    chunk.emit(make_abx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)obj_r, chunk.add_identifier(lv.name)));
            }
            if (lv.kind == LValue::FIELD_INDEX) {
                int field_r = alloc_reg();
                compile_into(StringExpr(lv.field), field_r);
                int inner_r = alloc_reg();
                chunk.emit(make_abc((uint8_t)Op::GET_INDEX, (uint8_t)inner_r, (uint8_t)obj_r, (uint8_t)field_r));
                int key_r = alloc_reg();
                compile_into(*lv.key, key_r);
                chunk.emit(make_abc((uint8_t)Op::SET_INDEX, (uint8_t)inner_r, (uint8_t)key_r, (uint8_t)val_r));
            } else {
                int key_r = alloc_reg();
                if (lv.kind == LValue::FIELD)
                    compile_into(StringExpr(lv.field), key_r);
                else
                    compile_into(*lv.key, key_r);
                chunk.emit(make_abc((uint8_t)Op::SET_INDEX, (uint8_t)obj_r, (uint8_t)key_r, (uint8_t)val_r));
            }
        }
    }

    reg_top_ = saved;
}

void Compiler::visit(const BlockStmt& s) {
    for (auto& stmt : s.stmts)
        stmt->accept(*this);
}

void Compiler::visit(const DoStmt& s) {
    compile_block(s.body);
}

// Compiles a method, with an implicit 'self' in R[0].
uint8_t Compiler::compile_method_func(const FuncDeclStmt& s) {
    return compile_func_body(s.name, s.params, s.defaults, s.body, s.variadic, s.is_static, !s.is_static, s.sloc());
}

void Compiler::visit(const ClassDeclStmt& s) {
    note_line(s.line, s.file_idx);
    int saved = reg_top_;

    // Create the class value (T_CLASS, an empty map).
    int dest = alloc_reg();
    chunk.emit(make_abc((uint8_t)Op::NEW_CLASS, (uint8_t)dest, 0, 0));

    // Store the class name as __name__, which print and debugging use.
    {
        int key_r = alloc_reg(), val_r = alloc_reg();
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.add_constant(Value(std::string("__name__")))));
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)val_r, chunk.add_constant(Value(s.name))));
        chunk.emit(make_abc((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_r, (uint8_t)val_r));
        reg_top_ = dest + 1;
    }

    // Inheritance: store the parent class as __parent__.
    if (!s.parent.empty()) {
        int par_r = alloc_reg(), key_r = alloc_reg();
        chunk.emit(make_abx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)par_r, chunk.add_identifier(s.parent)));
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.add_constant(Value(std::string("__parent__")))));
        chunk.emit(make_abc((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_r, (uint8_t)par_r));
        reg_top_ = dest + 1;
    }

    // 'super' inside those methods resolves through the LEXICAL parent class.
    std::string saved_parent = current_class_parent_;
    current_class_parent_ = s.parent;

    // Compile each method and store it in the class map.
    for (auto& method : s.methods) {
        // 'static' is forbidden on init and on the meta-methods: those calls — the constructor,
        // the operators — inject self by construction, so a static member there would silently
        // shift the arguments.
        if (method->is_static) {
            if (method->name == "init")
                throw std::runtime_error(method->sloc().str(chunk.source_files) +
                                         ": 'init' cannot be static (a constructor always has 'self')");
            if (method->name.size() >= 2 && method->name[0] == '_' && method->name[1] == '_')
                throw std::runtime_error(method->sloc().str(chunk.source_files) + ": metamethod '" + method->name +
                                         "' cannot be static (operators always have 'self')");
        }
        uint8_t func_idx = compile_method_func(*method);
        bool has_upvals = !chunk.funcs[func_idx].upvals.empty();

        int func_r = alloc_reg(), key_r = alloc_reg();
        if (has_upvals)
            chunk.emit(make_abx((uint8_t)Op::MAKE_CLOSURE, (uint8_t)func_r, func_idx));
        else
            chunk.emit(make_abx((uint8_t)Op::LOAD_FUNC, (uint8_t)func_r, func_idx));
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.add_constant(Value(method->name))));
        chunk.emit(make_abc((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_r, (uint8_t)func_r));
        reg_top_ = dest + 1;
    }

    current_class_parent_ = saved_parent;

    // Store the class as a global. The name is already in declared_globals_ through the
    // collect_globals pre-scan, which stays the single source of truth.
    chunk.emit(make_abx((uint8_t)Op::STORE_GLOBAL, (uint8_t)dest, chunk.add_identifier(s.name)));

    reg_top_ = saved;
}

// NEW_MAP, one (key, value) pair per element, SEAL_ENUM, then storage: a global
// for `enum Name`, or SET_INDEX on the target map for `enum a.b`. The sealing comes
// after the filling, which itself goes through SET_INDEX.
void Compiler::visit(const EnumDeclStmt& s) {
    note_line(s.line, s.file_idx);
    int saved = reg_top_;
    int dest = alloc_reg();
    chunk.emit(make_abc((uint8_t)Op::NEW_MAP, (uint8_t)dest, 0, 0));

    for (auto& it : s.items) {
        int item_saved = reg_top_;
        int key_r = alloc_reg();
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.add_constant(Value(it.name))));
        int val_r = alloc_reg();
        compile_into(*it.value, val_r);
        chunk.emit(make_abc((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_r, (uint8_t)val_r));
        reg_top_ = item_saved;
    }

    chunk.emit(make_abc((uint8_t)Op::SEAL_ENUM, (uint8_t)dest, 0, 0));

    if (!s.obj_expr) {
        // The name is already in declared_globals_ AND enum_names_ from the collect_globals pass.
        chunk.emit(make_abx((uint8_t)Op::STORE_GLOBAL, (uint8_t)dest, chunk.add_identifier(s.name)));
    } else {
        int obj_r = alloc_reg();
        compile_into(*s.obj_expr, obj_r);
        int key_r = alloc_reg();
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.add_constant(Value(s.name))));
        chunk.emit(make_abc((uint8_t)Op::SET_INDEX, (uint8_t)obj_r, (uint8_t)key_r, (uint8_t)dest));
    }

    reg_top_ = saved;
}

// Layout: R[call_base+0] is self, R[call_base+1] the method, R[call_base+2..] the arguments.
// CALL_METHOD shifts the arguments down by one, overwriting the method, before calling.
void Compiler::visit(const MethodCallExpr& e) {
    int call_base = reg_top_;
    int argc = (int)e.args.size();

    if (e.is_super) {
        // self lives in local_regs_["self"] and is copied to call_base. Outside a method 'self'
        // does not exist, hence a clean diagnostic instead of a map::at crash.
        auto self_it = local_regs_.find("self");
        if (self_it == local_regs_.end())
            throw std::runtime_error(sloc().str(chunk.source_files) + ": 'super' can only be used inside a method");
        // The parent class is fixed LEXICALLY — the class where the method is defined — rather
        // than through self.__class__.__parent__: otherwise B.m() running on a C instance would
        // always land back on B, an infinite recursion in a hierarchy of three levels or more.
        if (current_class_parent_.empty())
            throw std::runtime_error(sloc().str(chunk.source_files) + ": 'super': the current class has no parent");
        int self_src = self_it->second;
        reserve_regs_to(call_base + 1);
        chunk.emit(make_abc((uint8_t)Op::MOVE, (uint8_t)call_base, (uint8_t)self_src, 0));

        // Temporaries: tmp holds the parent class (a global), key_r the key.
        int tmp = alloc_reg(), key_r = alloc_reg();

        // tmp = <the lexically enclosing parent class>
        chunk.emit(make_abx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)tmp, chunk.add_identifier(current_class_parent_)));
        // R[call_base+1] = tmp.<method>
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.add_constant(Value(std::string(e.method)))));
        chunk.emit(make_abc((uint8_t)Op::GET_INDEX, (uint8_t)(call_base + 1), (uint8_t)tmp, (uint8_t)key_r));
        reserve_regs_to(call_base + 2);
    } else {
        // R[call_base] = receiver (self)
        compile_into(*e.receiver, call_base);
        reserve_regs_to(call_base + 1);

        // R[call_base+1] = GET_INDEX(receiver, method_name)
        int key_r = alloc_reg();
        chunk.emit(make_abx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.add_constant(Value(std::string(e.method)))));
        chunk.emit(make_abc((uint8_t)Op::GET_INDEX, (uint8_t)(call_base + 1), (uint8_t)call_base, (uint8_t)key_r));
        reserve_regs_to(call_base + 2);
    }

    // obj.m?() is `if m then m(args) else nil`: JUMP_IF_FALSE jumps BEFORE the arguments,
    // when the method (R[call_base+1]) is falsy, the arguments are not evaluated.
    size_t skip = 0;
    if (e.optional)
        skip = chunk.emit_jump(Op::JUMP_IF_FALSE, (uint8_t)(call_base + 1));

    // R[call_base+2..argc+1] = args
    compile_consecutive(call_base + 2, e.args);

    chunk.emit(make_abc((uint8_t)Op::CALL_METHOD, (uint8_t)call_base, 0, (uint8_t)argc));
    if (e.optional) {
        size_t end = chunk.emit_jump(Op::JUMP);                                // jumps over the LOAD_NIL
        chunk.patch_jump(skip, (uint16_t)chunk.current_pos());                 // the jump target: a nil method
        chunk.emit(make_abc((uint8_t)Op::LOAD_NIL, (uint8_t)call_base, 0, 0)); // a nil result
        chunk.patch_jump(end, (uint16_t)chunk.current_pos());
    }
    last_reg_ = call_base;
}
