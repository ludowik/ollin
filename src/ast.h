#pragma once
#include <memory>
#include <string>
#include <vector>

struct Expr { virtual ~Expr() = default; };

struct NumberExpr : Expr {
    double value;
    explicit NumberExpr(double v) : value(v) {}
};

struct VarExpr : Expr {
    std::string name;
    explicit VarExpr(std::string n) : name(std::move(n)) {}
};

struct BinaryExpr : Expr {
    char op;
    std::unique_ptr<Expr> left, right;
    BinaryExpr(char o, std::unique_ptr<Expr> l, std::unique_ptr<Expr> r)
        : op(o), left(std::move(l)), right(std::move(r)) {}
};

struct CallExpr : Expr {
    std::string callee;
    std::vector<std::unique_ptr<Expr>> args;
};

struct Stmt { virtual ~Stmt() = default; };

struct VarDeclStmt : Stmt {
    std::vector<std::string> names;
    std::vector<std::unique_ptr<Expr>> values;
};

struct ExprStmt : Stmt {
    std::unique_ptr<Expr> expr;
    explicit ExprStmt(std::unique_ptr<Expr> e) : expr(std::move(e)) {}
};

struct Program {
    std::vector<std::unique_ptr<Stmt>> stmts;
};
