#pragma once
#include <memory>
#include <string>
#include <vector>

// ── forward declarations ──────────────────────────────────────────────────────
struct CommentStmt; struct VarDeclStmt; struct WhileStmt;
struct IfStmt; struct BreakStmt; struct AssignStmt; struct ExprStmt;
struct ThrowStmt; struct TryCatchStmt; struct FuncDeclStmt; struct ReturnStmt;
struct ForStmt; struct IndexAssignStmt;

struct BoolExpr; struct NumberExpr; struct StringExpr; struct NilExpr;
struct VarExpr; struct BinaryExpr; struct UnaryExpr; struct CallExpr; struct VarArgExpr;
struct MapExpr; struct IndexExpr;

// ── interfaces visiteur ───────────────────────────────────────────────────────
struct StmtVisitor {
    virtual void visit(const CommentStmt&) = 0;
    virtual void visit(const VarDeclStmt&) = 0;
    virtual void visit(const WhileStmt&)   = 0;
    virtual void visit(const IfStmt&)      = 0;
    virtual void visit(const BreakStmt&)   = 0;
    virtual void visit(const AssignStmt&)  = 0;
    virtual void visit(const ExprStmt&)    = 0;
    virtual void visit(const ThrowStmt&)   = 0;
    virtual void visit(const TryCatchStmt&)  = 0;
    virtual void visit(const FuncDeclStmt&)  = 0;
    virtual void visit(const ReturnStmt&)    = 0;
    virtual void visit(const ForStmt&)       = 0;
    virtual void visit(const IndexAssignStmt&) = 0;
    virtual ~StmtVisitor() = default;
};

struct ExprVisitor {
    virtual void visit(const BoolExpr&)   = 0;
    virtual void visit(const NumberExpr&) = 0;
    virtual void visit(const StringExpr&) = 0;
    virtual void visit(const VarExpr&)    = 0;
    virtual void visit(const BinaryExpr&) = 0;
    virtual void visit(const CallExpr&)   = 0;
    virtual void visit(const UnaryExpr&)  = 0;
    virtual void visit(const VarArgExpr&) = 0;
    virtual void visit(const NilExpr&)    = 0;
    virtual void visit(const MapExpr&)    = 0;
    virtual void visit(const IndexExpr&)  = 0;
    virtual ~ExprVisitor() = default;
};

// ── classes de base ───────────────────────────────────────────────────────────
struct Stmt { virtual void accept(StmtVisitor&) const = 0; virtual ~Stmt() = default; };
struct Expr { virtual void accept(ExprVisitor&) const = 0; virtual ~Expr() = default; };

// ── expressions ───────────────────────────────────────────────────────────────
struct BoolExpr : Expr {
    bool value;
    explicit BoolExpr(bool v) : value(v) {}
    void accept(ExprVisitor& v) const override { v.visit(*this); }
};

struct NumberExpr : Expr {
    double value;
    explicit NumberExpr(double v) : value(v) {}
    void accept(ExprVisitor& v) const override { v.visit(*this); }
};

struct StringExpr : Expr {
    std::string value;
    explicit StringExpr(std::string v) : value(std::move(v)) {}
    void accept(ExprVisitor& v) const override { v.visit(*this); }
};

struct VarExpr : Expr {
    std::string name;
    explicit VarExpr(std::string n) : name(std::move(n)) {}
    void accept(ExprVisitor& v) const override { v.visit(*this); }
};

struct BinaryExpr : Expr {
    char op;
    std::unique_ptr<Expr> left, right;
    BinaryExpr(char o, std::unique_ptr<Expr> l, std::unique_ptr<Expr> r)
        : op(o), left(std::move(l)), right(std::move(r)) {}
    void accept(ExprVisitor& v) const override { v.visit(*this); }
};

struct UnaryExpr : Expr {
    char op;
    std::unique_ptr<Expr> operand;
    UnaryExpr(char o, std::unique_ptr<Expr> e) : op(o), operand(std::move(e)) {}
    void accept(ExprVisitor& v) const override { v.visit(*this); }
};

struct CallExpr : Expr {
    std::string callee;
    std::vector<std::unique_ptr<Expr>> args;
    void accept(ExprVisitor& v) const override { v.visit(*this); }
};

// ── instructions ──────────────────────────────────────────────────────────────
struct CommentStmt : Stmt {
    std::string text;
    explicit CommentStmt(std::string t) : text(std::move(t)) {}
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct VarDeclStmt : Stmt {
    std::vector<std::string> names;
    std::vector<std::unique_ptr<Expr>> values;
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct ExprStmt : Stmt {
    std::unique_ptr<Expr> expr;
    explicit ExprStmt(std::unique_ptr<Expr> e) : expr(std::move(e)) {}
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct AssignStmt : Stmt {
    std::string name;
    char        op;
    std::unique_ptr<Expr> value;
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct BreakStmt : Stmt {
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct ElseIfClause {
    std::unique_ptr<Expr> cond;
    std::vector<std::unique_ptr<Stmt>> body;
    ElseIfClause() = default;
    ElseIfClause(ElseIfClause&&) = default;
    ElseIfClause& operator=(ElseIfClause&&) = default;
};

struct IfStmt : Stmt {
    std::unique_ptr<Expr> cond;
    std::vector<std::unique_ptr<Stmt>> then_body;
    std::vector<ElseIfClause>          else_ifs;
    std::vector<std::unique_ptr<Stmt>> else_body;
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct WhileStmt : Stmt {
    std::unique_ptr<Expr> cond;
    std::vector<std::unique_ptr<Stmt>> body;
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct ThrowStmt : Stmt {
    std::unique_ptr<Expr> value;
    explicit ThrowStmt(std::unique_ptr<Expr> v) : value(std::move(v)) {}
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct TryCatchStmt : Stmt {
    std::vector<std::unique_ptr<Stmt>> try_body;
    std::string                        catch_var;
    std::vector<std::unique_ptr<Stmt>> catch_body;
    std::vector<std::unique_ptr<Stmt>> else_body;
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct FuncDeclStmt : Stmt {
    std::string name;
    std::vector<std::string> params;
    std::vector<std::unique_ptr<Expr>> defaults; // nullptr = pas de défaut
    bool variadic = false;
    std::vector<std::unique_ptr<Stmt>> body;
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct ReturnStmt : Stmt {
    std::vector<std::unique_ptr<Expr>> values;
    bool spread_varargs = false;
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct VarArgExpr : Expr {
    void accept(ExprVisitor& v) const override { v.visit(*this); }
};

struct NilExpr : Expr {
    void accept(ExprVisitor& v) const override { v.visit(*this); }
};

struct MapExpr : Expr {
    // keys are always strings (JSON-like)
    std::vector<std::pair<std::string, std::unique_ptr<Expr>>> entries;
    void accept(ExprVisitor& v) const override { v.visit(*this); }
};

struct IndexExpr : Expr {
    std::unique_ptr<Expr> obj;
    std::unique_ptr<Expr> key;
    void accept(ExprVisitor& v) const override { v.visit(*this); }
};

// for i in start..end   /   for i=start,end
struct ForStmt : Stmt {
    std::string var;
    std::unique_ptr<Expr> start;
    std::unique_ptr<Expr> end;
    std::unique_ptr<Expr> step;  // nullptr = step of 1 (forward only)
    std::vector<std::unique_ptr<Stmt>> body;
    void accept(StmtVisitor& v) const override { v.visit(*this); }
};

struct Program {
    std::vector<std::unique_ptr<Stmt>> stmts;
};
