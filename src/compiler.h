#pragma once
#include "ast.h"
#include "chunk.h"
#include <vector>

class Compiler {
public:
    Chunk compile(const Program& program);

private:
    Chunk chunk;
    std::vector<std::vector<size_t>> break_patches; // pile par boucle while

    void compileStmt(const Stmt& s);
    void compileVarDecl(const VarDeclStmt& s);
    void compileWhileStmt(const WhileStmt& s);
    void compileIfStmt(const IfStmt& s);
    void compileBreakStmt();
    void compileAssignStmt(const AssignStmt& s);
    void compileExprStmt(const ExprStmt& s);
    void compileExpr(const Expr& e);
};
