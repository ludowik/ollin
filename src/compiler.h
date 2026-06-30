#pragma once
#include "ast.h"
#include "chunk.h"
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class Compiler : public StmtVisitor, public ExprVisitor {
  public:
    Chunk compile(const Program& program);

  private:
    Chunk chunk;
    std::vector<std::vector<size_t>> break_patches;
    std::vector<std::vector<size_t>> continue_patches;
    int current_line_ = 0;

    // ── register allocator ────────────────────────────────────────────────────
    std::unordered_map<std::string, int> local_regs_;
    int reg_top_ = 0;    // next free register
    int reg_count_ = 0;  // max reg ever used → FuncProto.reg_count
    int locals_top_ = 0; // reg_top_ after pre-scanning locals (temps start here)
    int last_reg_ = -1;  // result register of last compiled expression

    // ── function scope ────────────────────────────────────────────────────────
    struct FuncInfo {
        uint8_t func_idx;
        int n_fixed;
        bool variadic;
        bool is_closure = false; // true = has upvalues, called via LOAD_GLOBAL+CALL_DYN
    };
    std::unordered_map<std::string, FuncInfo> func_table;
    std::unordered_set<std::string> declared_globals_; // globals déclarés (source + builtins + modules)
    std::unordered_set<std::string> const_names_;      // locals declared with 'const'
    std::string current_func_name;                     // "" = global scope
    int current_func_idx_ = -1;                        // index in chunk.funcs (-1 = main chunk)

    bool inFunction() const {
        return !current_func_name.empty();
    }

    // ── upvalue resolution ────────────────────────────────────────────────────
    struct OuterScope {
        std::unordered_map<std::string, int> regs;
        std::unordered_map<std::string, int> upval_idx; // name → upvalue index in this scope's proto
        std::unordered_set<std::string> consts;         // constants declared in this scope
        int func_proto_idx;                             // -1 = main chunk
    };
    std::vector<OuterScope> outer_scopes_;
    std::unordered_map<std::string, int> cur_upval_idx_;

    int resolveUpvalue(const std::string& name);
    int resolveUpvalFrom(int scope_idx, const std::string& name);
    int captureUpvalChain(int scope_idx, bool is_local, uint8_t idx, const std::string& name);
    uint8_t compileMethodFunc(const FuncDeclStmt& s);
    void compileIteratorLoop(const Expr& src, const std::string& var1, const std::string& var2,
                             const std::vector<std::unique_ptr<Stmt>>& body);
    // chemin rapide for numérique (range littéral inclus aux 2 bornes, 1 variable)
    void compileNumericFor(const RangeExpr& r, const std::string& var1, const std::vector<std::unique_ptr<Stmt>>& body);

    int allocReg() {
        int r = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        return r;
    }

    void compileInto(const Expr& e, int dest);

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
    void visit(const SwitchStmt&) override;

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

    // StmtVisitor (map)
    void visit(const IndexAssignStmt&) override;
    void visit(const MultiAssignStmt&) override;
};
