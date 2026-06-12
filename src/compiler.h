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

    // ── portée des fonctions ────────────────────────────────────────────────
    struct FuncInfo {
        int  addr;
        int  n_fixed;
        bool variadic;
        std::unordered_map<std::string, int> local_ids;
    };
    std::unordered_map<std::string, FuncInfo> func_table;
    FuncInfo* current_func = nullptr;

    void emitLoadVar (const std::string& name);
    void emitStoreVar(const std::string& name);

    // StmtVisitor
    void visit(const CommentStmt&)  override {}
    void visit(const VarDeclStmt&)  override;
    void visit(const WhileStmt&)    override;
    void visit(const IfStmt&)       override;
    void visit(const BreakStmt&)    override;
    void visit(const AssignStmt&)   override;
    void visit(const ExprStmt&)     override;
    void visit(const ThrowStmt&)    override;
    void visit(const TryCatchStmt&) override;
    void visit(const FuncDeclStmt&) override;
    void visit(const ReturnStmt&)   override;

    // ExprVisitor
    void visit(const BoolExpr&)   override;
    void visit(const NumberExpr&) override;
    void visit(const StringExpr&) override;
    void visit(const VarExpr&)    override;
    void visit(const BinaryExpr&) override;
    void visit(const CallExpr&)   override;
    void visit(const VarArgExpr&) override;
};
