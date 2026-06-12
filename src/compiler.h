#pragma once
#include "ast.h"
#include "chunk.h"
#include <vector>

class Compiler : public StmtVisitor, public ExprVisitor {
public:
    Chunk compile(const Program& program);

private:
    Chunk chunk;
    std::vector<std::vector<size_t>> break_patches;

    // StmtVisitor
    void visit(const CommentStmt&) override {}
    void visit(const VarDeclStmt&) override;
    void visit(const WhileStmt&)   override;
    void visit(const IfStmt&)      override;
    void visit(const BreakStmt&)   override;
    void visit(const AssignStmt&)  override;
    void visit(const ExprStmt&)    override;

    // ExprVisitor
    void visit(const BoolExpr&)   override;
    void visit(const NumberExpr&) override;
    void visit(const StringExpr&) override;
    void visit(const VarExpr&)    override;
    void visit(const BinaryExpr&) override;
    void visit(const CallExpr&)   override;
};
