#pragma once
#include "ast.h"
#include "chunk.h"
#include <string>
#include <unordered_map>
#include <vector>

class Compiler : public StmtVisitor, public ExprVisitor {
public:
    Chunk compile(const Program& program);

private:
    Chunk chunk;
    std::vector<std::vector<size_t>> break_patches;
    int for_counter_ = 0;

    // ── register allocator ────────────────────────────────────────────────────
    std::unordered_map<std::string, int> local_regs_;
    int reg_top_    = 0;  // next free register
    int reg_count_  = 0;  // max reg ever used → FuncProto.reg_count
    int locals_top_ = 0;  // reg_top_ after pre-scanning locals (temps start here)
    int last_reg_   = -1; // result register of last compiled expression

    // ── function scope ────────────────────────────────────────────────────────
    struct FuncInfo {
        uint8_t func_idx;
        int     n_fixed;
        bool    variadic;
    };
    std::unordered_map<std::string, FuncInfo> func_table;
    std::string current_func_name;  // "" = global scope

    bool inFunction() const { return !current_func_name.empty(); }

    int allocReg() {
        int r = reg_top_++;
        if (reg_top_ > reg_count_) reg_count_ = reg_top_;
        return r;
    }

    void compileInto(const Expr& e, int dest);

    // StmtVisitor
    void visit(const CommentStmt&)   override {}
    void visit(const VarDeclStmt&)   override;
    void visit(const WhileStmt&)     override;
    void visit(const IfStmt&)        override;
    void visit(const BreakStmt&)     override;
    void visit(const AssignStmt&)    override;
    void visit(const ExprStmt&)      override;
    void visit(const ThrowStmt&)     override;
    void visit(const TryCatchStmt&)  override;
    void visit(const FuncDeclStmt&)  override;
    void visit(const ReturnStmt&)    override;
    void visit(const ForStmt&)       override;

    // ExprVisitor
    void visit(const BoolExpr&)    override;
    void visit(const NumberExpr&)  override;
    void visit(const StringExpr&)  override;
    void visit(const VarExpr&)     override;
    void visit(const BinaryExpr&)  override;
    void visit(const CallExpr&)    override;
    void visit(const UnaryExpr&)   override;
    void visit(const VarArgExpr&)  override;
    void visit(const NilExpr&)     override;
    void visit(const MapExpr&)     override;
    void visit(const IndexExpr&)   override;

    // StmtVisitor (map)
    void visit(const IndexAssignStmt&) override;
};
