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

    TokenType peekNextType() const;
    void consumeLineEnd();   // absorbe un COMMENT de fin de ligne optionnel + NEWLINE

    std::unique_ptr<Stmt> parseOneStmt();
    std::unique_ptr<Stmt> varDecl();
    std::unique_ptr<Stmt> whileStmt();
    std::unique_ptr<Stmt> ifStmt();
    std::unique_ptr<Stmt> breakStmt();
    std::unique_ptr<Stmt> tryCatchStmt();
    std::unique_ptr<Stmt> throwStmt();
    std::unique_ptr<Stmt> funcDeclStmt();
    std::unique_ptr<Stmt> returnStmt();
    std::unique_ptr<Stmt> assignStmt();
    std::unique_ptr<Stmt> exprStmt();

    std::unique_ptr<Expr> expr();
    std::unique_ptr<Expr> logical();
    std::unique_ptr<Expr> logicalAnd();
    std::unique_ptr<Expr> comparison();
    std::unique_ptr<Expr> additive();
    std::unique_ptr<Expr> multiplicative();
    std::unique_ptr<Expr> unary();
    std::unique_ptr<Expr> primary();
};
