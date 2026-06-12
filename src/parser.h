#pragma once
#include "token.h"
#include "ast.h"
#include <vector>

class Parser {
public:
    explicit Parser(std::vector<Token> tokens);
    Program parse();

private:
    std::vector<Token> tokens;
    int pos = 0;

    Token peek() const;
    Token advance();
    bool check(TokenType t) const;
    bool match(TokenType t);
    Token expect(TokenType t);
    void skipNewlines();

    std::unique_ptr<Stmt> varDecl();
    std::unique_ptr<Stmt> exprStmt();
    std::unique_ptr<Expr> expr();
    std::unique_ptr<Expr> additive();
    std::unique_ptr<Expr> multiplicative();
    std::unique_ptr<Expr> primary();
};
