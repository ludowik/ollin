#pragma once
#include "ast.h"
#include "chunk.h"
#include <functional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class Compiler : public StmtVisitor, public ExprVisitor {
  public:
    Chunk compile(const Program& program);

  private:
    Chunk chunk;
    // One frame per enclosing construct a `break` or a `continue` could target, innermost last.
    // Beyond the jumps to patch, a frame records WHERE it was opened, which is what lets the two
    // statements be refused instead of jumping somewhere absurd: `func_depth` catches a break
    // written inside a lambda, whose jump would land in the enclosing FUNCTION's code, and
    // `is_switch` catches a break inside a switch, which is silently not the loop's.
    struct JumpTargets {
        std::vector<size_t> patches;
        size_t func_depth = 0;
        int try_depth = 0;      // active try blocks when opened: a jump out of one must pop it
        bool is_switch = false; // only ever true for break: a switch does not catch continue
    };
    int try_depth_ = 0; // try bodies being compiled, the catch bodies excluded
    // The try depth on entering each nested function body: a `return` only leaves the try blocks
    // of ITS function, so the count is taken from this floor and not from zero.
    std::vector<int> try_floors_;
    int try_floor() const {
        return try_floors_.empty() ? 0 : try_floors_.back();
    }
    std::vector<JumpTargets> break_patches;
    std::vector<JumpTargets> continue_patches;
    void check_jump_scope(const Stmt& s, const std::vector<JumpTargets>& frames, const char* what);
    void pop_crossed_tries(const JumpTargets& frame);
    int current_line_ = 0;
    int current_file_idx_ = 0;

    std::unordered_map<std::string, int> local_regs_;
    // `var` and `const` locals whose register is reserved but which are NOT declared yet: lexical
    // scope makes them visible only from their own line on. A reference before the declaration
    // therefore does not find them in local_regs_ and falls through to a global, an upvalue, or an
    // error. They are activated — moved into local_regs_ — at the VarDeclStmt, and this map is saved
    // and restored wherever local_regs_ is, for nested scopes.
    std::unordered_map<std::string, int> pending_var_reg_;
    int reg_top_ = 0;    // next free register
    int reg_count_ = 0;  // max reg ever used → FuncProto.reg_count
    int locals_top_ = 0; // reg_top_ after pre-scanning locals (temps start here)
    int last_reg_ = -1;  // result register of last compiled expression

    struct FuncInfo {
        uint8_t func_idx;
        int n_fixed;
        bool variadic;
        bool is_closure = false; // true = has upvalues, called via LOAD_GLOBAL+CALL_DYN
    };
    std::unordered_map<std::string, FuncInfo> func_table;
    std::unordered_set<std::string>
        declared_globals_;                        // the declared globals: the source's, the builtins and the modules
    std::unordered_set<std::string> const_names_; // locals declared with 'const'
    // Enums declared under a plain name, so that visible writes are refused at compile time with a
    // message naming the element. The VM still covers every other path.
    std::unordered_set<std::string> enum_names_;
    std::string current_func_name; // "" = global scope
    // Name of the parent of the class whose method is being compiled; empty outside a class, or for
    // a class with no parent. 'super' resolves through THIS lexical class and not through self's
    // dynamic class, which would recurse forever in a hierarchy of three levels or more.
    std::string current_class_parent_;
    int current_func_idx_ = -1; // index in chunk.funcs (-1 = main chunk)

    bool in_function() const {
        return !current_func_name.empty();
    }

    struct OuterScope {
        std::unordered_map<std::string, int> regs;
        std::unordered_map<std::string, int> upval_idx; // name → upvalue index in this scope's proto
        std::unordered_set<std::string> consts;         // constants declared in this scope
        int func_proto_idx;                             // -1 = main chunk
    };
    std::vector<OuterScope> outer_scopes_;
    std::unordered_map<std::string, int> cur_upval_idx_;

    // Everything the ENCLOSING scope owns while a function body is compiled. Saved and reset by
    // the constructor, restored by the destructor: the nine fields were saved and restored by
    // hand in three places, in the same order, and one forgotten restore would not fail to
    // compile — it would silently corrupt the scope of everything that follows.
    struct FuncScope {
        Compiler& c;
        std::unordered_map<std::string, int> regs, pending, upvals;
        std::unordered_set<std::string> consts;
        int top, count, locals, fidx;
        std::string name;
        FuncScope(Compiler& comp, const std::string& fname);
        ~FuncScope();
    };
    // Compiles a function body into a fresh FuncProto and returns its index. `with_self` puts
    // self in R[0] (an instance method), and on_registered runs once the proto exists but
    // BEFORE the body — which is what lets a top-level function be recursive.
    uint8_t compile_func_body(const std::string& name, const std::vector<std::string>& params,
                              const std::vector<std::unique_ptr<Expr>>& defaults,
                              const std::vector<std::unique_ptr<Stmt>>& body, bool variadic, bool is_static,
                              bool with_self, SourceLoc defaults_loc,
                              const std::function<void(uint8_t)>& on_registered = {});

    int resolve_upvalue(const std::string& name);
    int resolve_upval_from(int scope_idx, const std::string& name);
    int capture_upval_chain(int scope_idx, bool is_local, uint8_t idx, const std::string& name);
    uint8_t compile_method_func(const FuncDeclStmt& s);
    void compile_iterator_loop(const Expr& src, const std::string& var1, const std::string& var2,
                               const std::vector<std::unique_ptr<Stmt>>& body);
    // Fast path for the numeric for: a range literal inclusive on both bounds, one variable.
    void compile_numeric_for(const RangeExpr& r, const std::string& var1,
                             const std::vector<std::unique_ptr<Stmt>>& body);

    // reg_count_ is the HIGH-WATER MARK of reg_top_: it is what FuncProto.reg_count commits to,
    // and what bounds a builtin's result slots (see "Invariant registre" in CLAUDE.md). Every
    // site that moves reg_top_ must raise it, so the rule lives here instead of in the fifty
    // copies of `if (reg_top_ > reg_count_)` it used to be written as — one forgotten copy
    // under-reports reg_count and lets a builtin write outside its frame.
    void bump_reg_count() {
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
    }
    void reserve_regs_to(int top) {
        reg_top_ = top;
        bump_reg_count();
    }
    int alloc_reg() {
        int r = reg_top_++;
        bump_reg_count();
        return r;
    }
    // n consecutive registers, the base returned.
    int alloc_regs(int n) {
        int base = reg_top_;
        reg_top_ += n;
        bump_reg_count();
        return base;
    }

    // Records the current source line for runtime diagnostics, replacing the
    // `if (line > 0) { current_line_ = line; chunk.set_line(line); }` prologue that used to be
    // duplicated in every visit().
    void note_line(int line, int fi = -1) {
        if (line > 0) {
            current_line_ = line;
            if (fi >= 0)
                current_file_idx_ = fi;
            chunk.set_line(line, current_file_idx_);
        }
    }

    SourceLoc sloc() const {
        return {(uint16_t)current_file_idx_, (uint16_t)current_line_};
    }

    // "file:line" for a diagnostic, falling back on the last line seen when the node carries
    // none — a node the PARSER generated (an import's alias map, say) has no line of its own.
    std::string where(int line, int file_idx) const {
        return SourceLoc{(uint16_t)file_idx, (uint16_t)(line > 0 ? line : current_line_)}.str(chunk.source_files);
    }
    std::string where(const Stmt& s) const {
        return where(s.line, s.file_idx);
    }

    // Compiles e so its value ends up in `dest`. `dest_at_top` says dest is the TOP of the
    // scratch area — the argument slots of a call, the values of a return — which lets a node
    // that allocates its own register land on dest itself instead of being copied there.
    void compile_into(const Expr& e, int dest, bool dest_at_top = false);
    // `count` < 0 means the whole list: a call with a spread last argument compiles only the
    // fixed ones through here.
    void compile_consecutive(int base, const std::vector<std::unique_ptr<Expr>>& exprs, int count = -1);
    // Strict lexical scope: saves local_regs_, reg_top_ and locals_top_, allocates the locals
    // declared in body without descending into sub-blocks, compiles, then restores. The registers
    // stay reserved when the body contains closures.
    // `pre_bound` names a variable already living in `pre_bound_reg` — the catch variable, the
    // only case — so it keeps that register instead of being given a fresh one.
    void compile_block(const std::vector<std::unique_ptr<Stmt>>& body, const std::string& pre_bound = "",
                       int pre_bound_reg = 0);
    // A sequence of statements, each one's temporaries freed after it — EXCEPT when it carries a
    // function, whose captured registers must stay reserved.
    void compile_stmt_seq(const std::vector<std::unique_ptr<Stmt>>& body);
    // "does this body carry a function?", MEMOIZED by the address of the body. The walk is
    // recursive, and the same body is asked three to four times per enclosing construct
    // (compile_block, the closing of a scope, keep_captured_regs, the alias test), so the cost
    // was proportional to the nesting depth. The key is only valid for one compilation, hence a
    // member and not a static.
    bool body_carries_func(const std::vector<std::unique_ptr<Stmt>>& body);
    int keep_captured_regs(const std::vector<std::unique_ptr<Stmt>>& body, int loop_vars_top, int recycled_top,
                           int reg_top_after_body);
    std::unordered_map<const void*, bool> has_func_cache_;

    // Reserves a register for every pre-scanned local. Functions are bound in local_regs_ straight
    // away, for recursion and forward references, while var and const are deferred in
    // pending_var_reg_ for lexical scope. `skip` holds the names from the CURRENT scope's prologue
    // (parameters, self, the catch variable), left as they are. A name inherited from an enclosing
    // scope is NOT in skip, so it gets a fresh register and shadows the outer one.
    void bind_scan_locals(const std::vector<std::string>& names, const std::unordered_set<std::string>& funcs,
                          const std::unordered_set<std::string>& skip = {});

    // Loads the callable named `name` into register `reg`: a local, an upvalue, a top-level function
    // through LOAD_FUNC, or a global through LOAD_GLOBAL.
    void emit_callee_value(const std::string& name, int reg);
    // Compiles a call whose LAST argument is multi-valued, either `...` or a call: the callee sits
    // below the argument block, then the fixed arguments, then the expansion — emitting CALL_VARARGS
    // for `...` and CALL_VA for a call. emit_callee(reg) places the callable, and the result comes
    // back through last_reg_ = call_base.
    void emit_spread_call(const std::vector<std::unique_ptr<Expr>>& args, const std::function<void(int)>& emit_callee);
    // `f?(args)`: the callee is placed FIRST so it can be tested, then the arguments — which a
    // falsy callee therefore never evaluates. Shared by the named and the expression forms,
    // which differed only in how emit_callee(reg) puts the callable there.
    void emit_optional_call(const std::vector<std::unique_ptr<Expr>>& args,
                            const std::function<void(int)>& emit_callee);

    // StmtVisitor
    void visit(const CommentStmt&) override {
    }
    void visit(const VarDeclStmt&) override;
    void visit(const WhileStmt&) override;
    void visit(const IfStmt&) override;
    void visit(const BreakStmt&) override;
    void visit(const ContinueStmt&) override;
    void visit(const AssignStmt&) override;
    void visit(const ExprStmt&) override;
    void visit(const ThrowStmt&) override;
    void visit(const TryCatchStmt&) override;
    void visit(const FuncDeclStmt&) override;
    void visit(const ReturnStmt&) override;

    void visit(const ForIterStmt&) override;
    void visit(const BlockStmt&) override;
    void visit(const ClassDeclStmt&) override;
    void visit(const EnumDeclStmt&) override;
    void visit(const SwitchStmt&) override;
    void visit(const DoStmt&) override;

    // Refuses a write to an enum, detected at compile time so the message can name the enumeration
    // and the element. An empty `field` means the key is not a literal.
    void reject_enum_write(const std::string& obj_name, const Expr* obj_expr, const std::string& field, int line,
                           int file_idx);

    // ExprVisitor
    void visit(const BoolExpr&) override;
    void visit(const NumberExpr&) override;
    void visit(const StringExpr&) override;
    void visit(const VarExpr&) override;
    void visit(const BinaryExpr&) override;
    void visit(const CallExpr&) override;
    void visit(const UnaryExpr&) override;
    void visit(const VarArgExpr&) override;
    void visit(const NilExpr&) override;
    void visit(const MapExpr&) override;
    void visit(const IndexExpr&) override;
    void visit(const ArrayExpr&) override;
    void visit(const ExprCallExpr&) override;
    void visit(const MethodCallExpr&) override;
    void visit(const RangeExpr&) override;
    void visit(const FuncExpr&) override;
    void visit(const ChainedCompareExpr&) override;
    void visit(const InterpExpr&) override;

    // StmtVisitor (map)
    void visit(const IndexAssignStmt&) override;
    void visit(const MultiAssignStmt&) override;
};
