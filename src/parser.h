#pragma once
#include "ast.h"
#include "token.h"
#include <memory>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class Parser {
  public:
    explicit Parser(std::vector<Token> tokens, std::string base_dir = "",
                    std::shared_ptr<std::unordered_set<std::string>> imported = nullptr,
                    std::shared_ptr<std::unordered_map<std::string, std::vector<std::string>>> module_names = nullptr);
    Program parse();

  private:
    std::vector<Token> tokens;
    int pos = 0;
    std::string base_dir_;
    std::shared_ptr<std::unordered_set<std::string>> imported_paths_;
    // Cache partagé path résolu → noms top-level exportés, pour bâtir la map d'un
    // import aliasé même quand le module a déjà été importé (dédup ≠ cycle).
    std::shared_ptr<std::unordered_map<std::string, std::vector<std::string>>> module_names_;
    int depth_ = 0; // profondeur de récursion (garde anti-débordement de pile)

    const Token& peek() const;
    const Token& advance();
    bool check(TokenType t) const;
    bool match(TokenType t);
    Token expect(TokenType t);
    void skipComments();

    TokenType peekNextType() const;
    TokenType peekAt(int offset) const;
    void consumeOptComment(); // absorbe un COMMENT optionnel

    std::unique_ptr<Stmt> parseOneStmt();
    std::unique_ptr<Stmt> varDecl();
    std::unique_ptr<Stmt> globalDecl();
    std::unique_ptr<Stmt> constantDecl();
    std::unique_ptr<Stmt> whileStmt();
    std::unique_ptr<Stmt> ifStmt();
    std::unique_ptr<Stmt> breakStmt();
    std::unique_ptr<Stmt> continueStmt();
    std::unique_ptr<Stmt> tryCatchStmt();
    std::unique_ptr<Stmt> throwStmt();
    std::unique_ptr<Stmt> funcDeclStmt();
    std::unique_ptr<Stmt> returnStmt();
    std::unique_ptr<Stmt> multiAssignStmt();
    std::unique_ptr<Stmt> exprStmt();
    // Construit l'instruction d'affectation à partir d'une cible déjà parsée
    // (VarExpr → AssignStmt ; IndexExpr → IndexAssignStmt chaîné). Rejette toute
    // autre forme (« invalid assignment target »).
    std::unique_ptr<Stmt> finishAssignFromExpr(std::unique_ptr<Expr> target, int line);
    std::unique_ptr<Stmt> forStmt();
    std::unique_ptr<Stmt> importStmt();
    std::unique_ptr<Stmt> classDecl();
    std::unique_ptr<Stmt> switchStmt();

    std::unique_ptr<Expr> parsePostfix(std::unique_ptr<Expr> base);

    std::unique_ptr<Expr> expr();
    std::unique_ptr<Expr> logical();
    std::unique_ptr<Expr> logicalAnd();
    std::unique_ptr<Expr> bitwiseOr();
    std::unique_ptr<Expr> bitwiseXor();
    std::unique_ptr<Expr> bitwiseAnd();
    std::unique_ptr<Expr> comparison();
    std::unique_ptr<Expr> shift();
    std::unique_ptr<Expr> additive();
    std::unique_ptr<Expr> multiplicative();
    std::unique_ptr<Expr> power();
    std::unique_ptr<Expr> unary();
    std::unique_ptr<Expr> primary();

    // Range parsing helpers
    bool looksLikeRange() const;                     // scan from current pos for SEMICOLON before COMMA/RBRACKET
    std::unique_ptr<Expr> rangeExpr(bool incl_left); // parse rest after [ or ]
};
