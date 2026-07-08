#pragma once
#include "token.h"
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

// ── forward declarations ──────────────────────────────────────────────────────
struct CommentStmt;
struct VarDeclStmt;
struct WhileStmt;
struct IfStmt;
struct BreakStmt;
struct ContinueStmt;
struct AssignStmt;
struct ExprStmt;
struct ThrowStmt;
struct TryCatchStmt;
struct FuncDeclStmt;
struct ReturnStmt;
struct ForIterStmt;
struct IndexAssignStmt;
struct MultiAssignStmt;
struct BlockStmt;
struct ClassDeclStmt;
struct SwitchStmt;

struct BoolExpr;
struct NumberExpr;
struct StringExpr;
struct NilExpr;
struct VarExpr;
struct BinaryExpr;
struct UnaryExpr;
struct CallExpr;
struct VarArgExpr;
struct MapExpr;
struct IndexExpr;
struct ArrayExpr;
struct ExprCallExpr;
struct MethodCallExpr;
struct RangeExpr;
struct FuncExpr;
struct ChainedCompareExpr;

// ── interfaces visiteur ───────────────────────────────────────────────────────
struct StmtVisitor {
    virtual void visit(const CommentStmt&) = 0;
    virtual void visit(const VarDeclStmt&) = 0;
    virtual void visit(const WhileStmt&) = 0;
    virtual void visit(const IfStmt&) = 0;
    virtual void visit(const BreakStmt&) = 0;
    virtual void visit(const ContinueStmt&) = 0;
    virtual void visit(const AssignStmt&) = 0;
    virtual void visit(const ExprStmt&) = 0;
    virtual void visit(const ThrowStmt&) = 0;
    virtual void visit(const TryCatchStmt&) = 0;
    virtual void visit(const FuncDeclStmt&) = 0;
    virtual void visit(const ReturnStmt&) = 0;

    virtual void visit(const IndexAssignStmt&) = 0;
    virtual void visit(const MultiAssignStmt&) = 0;
    virtual void visit(const ForIterStmt&) = 0;
    virtual void visit(const BlockStmt&) = 0;
    virtual void visit(const ClassDeclStmt&) = 0;
    virtual void visit(const SwitchStmt&) = 0;
    virtual ~StmtVisitor() = default;
};

struct ExprVisitor {
    virtual void visit(const BoolExpr&) = 0;
    virtual void visit(const NumberExpr&) = 0;
    virtual void visit(const StringExpr&) = 0;
    virtual void visit(const VarExpr&) = 0;
    virtual void visit(const BinaryExpr&) = 0;
    virtual void visit(const CallExpr&) = 0;
    virtual void visit(const UnaryExpr&) = 0;
    virtual void visit(const VarArgExpr&) = 0;
    virtual void visit(const NilExpr&) = 0;
    virtual void visit(const MapExpr&) = 0;
    virtual void visit(const IndexExpr&) = 0;
    virtual void visit(const ArrayExpr&) = 0;
    virtual void visit(const ExprCallExpr&) = 0;
    virtual void visit(const MethodCallExpr&) = 0;
    virtual void visit(const RangeExpr&) = 0;
    virtual void visit(const FuncExpr&) = 0;
    virtual void visit(const ChainedCompareExpr&) = 0;
    virtual ~ExprVisitor() = default;
};

// ── classes de base ───────────────────────────────────────────────────────────
struct Stmt {
    int line = 0;
    virtual void accept(StmtVisitor&) const = 0;
    virtual ~Stmt() = default;
};
// Base pour les visiteurs lecture seule : méthodes non overridées = no-op.
struct StmtQuery : StmtVisitor {
    void run(const std::vector<std::unique_ptr<Stmt>>& stmts) {
        for (auto& s : stmts)
            s->accept(*this);
    }
    void visit(const CommentStmt&) override {
    }
    void visit(const VarDeclStmt&) override {
    }
    void visit(const WhileStmt&) override {
    }
    void visit(const IfStmt&) override {
    }
    void visit(const BreakStmt&) override {
    }
    void visit(const ContinueStmt&) override {
    }
    void visit(const AssignStmt&) override {
    }
    void visit(const ExprStmt&) override {
    }
    void visit(const ThrowStmt&) override {
    }
    void visit(const TryCatchStmt&) override {
    }
    void visit(const FuncDeclStmt&) override {
    }
    void visit(const ReturnStmt&) override {
    }
    void visit(const IndexAssignStmt&) override {
    }
    void visit(const MultiAssignStmt&) override {
    }
    void visit(const ForIterStmt&) override {
    }
    void visit(const BlockStmt&) override {
    }
    void visit(const ClassDeclStmt&) override {
    }
    void visit(const SwitchStmt&) override {
    }
};
struct Expr {
    int line = 0;
    virtual void accept(ExprVisitor&) const = 0;
    virtual ~Expr() = default;
};

// ── expressions ───────────────────────────────────────────────────────────────
struct BoolExpr : Expr {
    bool value;
    explicit BoolExpr(bool v) : value(v) {
    }
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct NumberExpr : Expr {
    double value;
    int64_t ival;
    bool is_integer;
    explicit NumberExpr(double v) : value(v), ival(0), is_integer(false) {
    }
    explicit NumberExpr(int64_t v) : value(0.0), ival(v), is_integer(true) {
    }
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct StringExpr : Expr {
    std::string value;
    explicit StringExpr(std::string v) : value(std::move(v)) {
    }
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct VarExpr : Expr {
    std::string name;
    explicit VarExpr(std::string n) : name(std::move(n)) {
    }
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct BinaryExpr : Expr {
    char op;
    std::unique_ptr<Expr> left, right;
    BinaryExpr(char o, std::unique_ptr<Expr> l, std::unique_ptr<Expr> r)
        : op(o), left(std::move(l)), right(std::move(r)) {
    }
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct UnaryExpr : Expr {
    char op;
    std::unique_ptr<Expr> operand;
    UnaryExpr(char o, std::unique_ptr<Expr> e) : op(o), operand(std::move(e)) {
    }
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

// 1 < x < 10  →  (1 < x) and (x < 10), x évalué une seule fois
// ops[i] est le char-opérateur entre operands[i] et operands[i+1]
struct ChainedCompareExpr : Expr {
    std::vector<std::unique_ptr<Expr>> operands;
    std::vector<char> ops;
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct CallExpr : Expr {
    std::string callee;
    std::vector<std::unique_ptr<Expr>> args;
    bool optional = false; // f?() : n'appelle que si callable, sinon nil
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

// ── instructions ──────────────────────────────────────────────────────────────
struct CommentStmt : Stmt {
    std::string text;
    explicit CommentStmt(std::string t) : text(std::move(t)) {
    }
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct VarDeclStmt : Stmt {
    std::vector<std::string> names;
    std::vector<std::unique_ptr<Expr>> values;
    bool is_global = false;   // true = déclaré avec 'global' → variables globales
    bool is_constant = false; // true = déclaré avec 'constant' → locale immuable
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct ExprStmt : Stmt {
    std::unique_ptr<Expr> expr;
    explicit ExprStmt(std::unique_ptr<Expr> e) : expr(std::move(e)) {
    }
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct AssignStmt : Stmt {
    std::string name;
    char op = '\0'; // '\0' = affectation simple ; '+','-','*','/','%' = compound
    std::unique_ptr<Expr> value;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct BreakStmt : Stmt {
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct ContinueStmt : Stmt {
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
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
    std::vector<ElseIfClause> else_ifs;
    std::vector<std::unique_ptr<Stmt>> else_body;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct WhileStmt : Stmt {
    std::unique_ptr<Expr> cond;
    std::vector<std::unique_ptr<Stmt>> body;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct ThrowStmt : Stmt {
    std::unique_ptr<Expr> value;
    explicit ThrowStmt(std::unique_ptr<Expr> v) : value(std::move(v)) {
    }
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct TryCatchStmt : Stmt {
    std::vector<std::unique_ptr<Stmt>> try_body;
    std::string catch_var;
    std::vector<std::unique_ptr<Stmt>> catch_body;
    std::vector<std::unique_ptr<Stmt>> else_body;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct FuncDeclStmt : Stmt {
    std::string name;
    std::vector<std::string> params;
    std::vector<std::unique_ptr<Expr>> defaults; // nullptr = pas de défaut
    bool variadic = false;
    bool is_static = false; // méthode de classe (pas de self implicite)
    std::vector<std::unique_ptr<Stmt>> body;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct ReturnStmt : Stmt {
    std::vector<std::unique_ptr<Expr>> values;
    bool spread_varargs = false;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct VarArgExpr : Expr {
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct NilExpr : Expr {
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct MapEntry {
    // key : StringExpr littéral pour `ident:` / `"s":` / `["s"]:` ;
    //       expression quelconque pour les clés calculées `[expr]:`
    std::unique_ptr<Expr> key;
    std::unique_ptr<Expr> value;
};

struct MapExpr : Expr {
    std::vector<MapEntry> entries;
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct IndexExpr : Expr {
    std::unique_ptr<Expr> obj;
    std::unique_ptr<Expr> key;
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct IndexAssignStmt : Stmt {
    std::string obj; // nom de la variable conteneur (utilisé si obj_expr est nul)
    // Conteneur sous forme d'EXPRESSION pour les cibles CHAÎNÉES (a.b.c, a[i][j],
    // a.b[k]…). Si non nul, prime sur `obj` : le compilateur l'évalue pour obtenir
    // la map/array à indexer. Sinon on retombe sur le nom simple `obj`.
    std::unique_ptr<Expr> obj_expr;
    std::unique_ptr<Expr> key;
    TokenType op = TokenType::EQUALS; // EQUALS, PLUS_EQUAL, MINUS_EQUAL, etc.
    std::unique_ptr<Expr> value;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct LValue {
    enum Kind { VAR, FIELD, INDEX, FIELD_INDEX };
    Kind kind = VAR;
    std::string name;               // VAR: variable; FIELD/INDEX/FIELD_INDEX: object name
    std::string field;              // FIELD et FIELD_INDEX: nom du champ
    std::unique_ptr<Expr> key;      // INDEX et FIELD_INDEX: expression d'index
};

struct MultiAssignStmt : Stmt {
    std::vector<LValue> targets;
    std::vector<std::unique_ptr<Expr>> values;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

// for [var1,] var2 in iterable_expr
// 1 var  → var1 reçoit la valeur primaire (val pour array/range, key pour map)
// 2 vars → var1=key/index, var2=val
struct ForIterStmt : Stmt {
    std::string var1; // toujours lié (key si 2 vars, primary si 1 var)
    std::string var2; // vide = forme 1 var
    std::unique_ptr<Expr> iter_expr;
    std::vector<std::unique_ptr<Stmt>> body;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct BlockStmt : Stmt {
    std::vector<std::unique_ptr<Stmt>> stmts;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct ArrayExpr : Expr {
    std::vector<std::unique_ptr<Expr>> elements;
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct RangeExpr : Expr {
    bool incl_left = true;  // '[' = true, ']' = false (open-left)
    bool incl_right = true; // ']' = true, '[' = false (open-right)
    std::unique_ptr<Expr> start;
    std::unique_ptr<Expr> end;
    std::unique_ptr<Expr> step; // nullptr if absent
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct FuncExpr : Expr {
    std::vector<std::string> params;
    std::vector<std::unique_ptr<Expr>> defaults;
    bool variadic = false;
    std::vector<std::unique_ptr<Stmt>> body;
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

// Appel via une expression (callee quelconque : IndexExpr, CallExpr, VarExpr…)
struct ExprCallExpr : Expr {
    std::unique_ptr<Expr> callee;
    std::vector<std::unique_ptr<Expr>> args;
    bool optional = false; // expr?() : n'appelle que si callable, sinon nil
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

// Appel de méthode : receiver.method(args) — self auto-passé
struct MethodCallExpr : Expr {
    std::unique_ptr<Expr> receiver; // nullptr si is_super
    std::string method;
    std::vector<std::unique_ptr<Expr>> args;
    bool is_super = false;
    bool optional = false; // obj.m?() : appelle si la méthode est callable, nil si absente
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

// Déclaration de classe
struct ClassDeclStmt : Stmt {
    std::string name;
    std::string parent; // vide si pas d'extends
    std::vector<std::unique_ptr<FuncDeclStmt>> methods;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct CaseClause {
    std::vector<std::unique_ptr<Expr>> values;
    std::vector<std::unique_ptr<Stmt>> body;
    CaseClause() = default;
    CaseClause(CaseClause&&) = default;
    CaseClause& operator=(CaseClause&&) = default;
};

struct SwitchStmt : Stmt {
    std::unique_ptr<Expr> subject;
    std::vector<CaseClause> cases;
    std::vector<std::unique_ptr<Stmt>> else_body;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct Program {
    std::vector<std::unique_ptr<Stmt>> stmts;
};
