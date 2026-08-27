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
        int try_depth = 0;        // active try blocks when opened: a jump out of one must pop it
        bool is_switch = false;   // only ever true for break: a switch does not catch continue
    };
    int try_depth_ = 0;           // try bodies being compiled, the catch bodies excluded
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
    std::unordered_set<std::string> declared_globals_; // the declared globals: the source's, the builtins and the modules
    std::unordered_set<std::string> const_names_;      // locals declared with 'const'
    // Enums declared under a plain name, so that visible writes are refused at compile time with a
    // message naming the element. The VM still covers every other path.
    std::unordered_set<std::string> enum_names_;
    std::string current_func_name;                     // "" = global scope
    // Name of the parent of the class whose method is being compiled; empty outside a class, or for
    // a class with no parent. 'super' resolves through THIS lexical class and not through self's
    // dynamic class, which would recurse forever in a hierarchy of three levels or more.
    std::string current_class_parent_;
    int current_func_idx_ = -1;                        // index in chunk.funcs (-1 = main chunk)

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

    int resolve_upvalue(const std::string& name);
    int resolve_upval_from(int scope_idx, const std::string& name);
    int capture_upval_chain(int scope_idx, bool is_local, uint8_t idx, const std::string& name);
    uint8_t compile_method_func(const FuncDeclStmt& s);
    void compile_iterator_loop(const Expr& src, const std::string& var1, const std::string& var2,
                             const std::vector<std::unique_ptr<Stmt>>& body);
    // Fast path for the numeric for: a range literal inclusive on both bounds, one variable.
    void compile_numeric_for(const RangeExpr& r, const std::string& var1, const std::vector<std::unique_ptr<Stmt>>& body);

    int alloc_reg() {
        int r = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        return r;
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

    SourceLoc sloc() const { return {(uint16_t)current_file_idx_, (uint16_t)current_line_}; }

    void compile_into(const Expr& e, int dest);
    void compile_consecutive(int base, const std::vector<std::unique_ptr<Expr>>& exprs);
    // Strict lexical scope: saves local_regs_, reg_top_ and locals_top_, allocates the locals
    // declared in body without descending into sub-blocks, compiles, then restores. The registers
    // stay reserved when the body contains closures.
    void compile_block(const std::vector<std::unique_ptr<Stmt>>& body);

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
    void emit_spread_call(const std::vector<std::unique_ptr<Expr>>& args,
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
