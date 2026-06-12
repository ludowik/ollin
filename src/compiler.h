#pragma once
#include "ast.h"
#include "chunk.h"

class Compiler {
public:
    Chunk compile(const Program& program);

private:
    Chunk chunk;

    void compileStmt(const Stmt& s);
    void compileVarDecl(const VarDeclStmt& s);
    void compileExprStmt(const ExprStmt& s);
    void compileExpr(const Expr& e);
};
