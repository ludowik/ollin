#pragma once
#include "source_loc.h"
#include "token.h"
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

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
struct EnumDeclStmt;
struct SwitchStmt;
struct DoStmt;

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
struct InterpExpr;

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
    virtual void visit(const EnumDeclStmt&) = 0;
    virtual void visit(const SwitchStmt&) = 0;
    virtual void visit(const DoStmt&) = 0;
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
    virtual void visit(const InterpExpr&) = 0;
    virtual ~ExprVisitor() = default;
};

struct Stmt;
// Callback handed to Stmt::for_each_body, once per sub-body.
using BodyFn = std::function<void(const std::vector<std::unique_ptr<Stmt>>&)>;

struct Stmt {
    int line = 0;
    int file_idx = 0;
    SourceLoc sloc() const {
        return {(uint16_t)file_idx, (uint16_t)line};
    }
    virtual void accept(StmtVisitor&) const = 0;
    // Names this statement declares at module level, hence stored in the map built by
    // `import "m" as m` (none by default). The answer lives HERE, next to the node: a new kind
    // of declaring statement must answer, or its names stay invisible to imports — which is
    // exactly what happened to `enum`.
    virtual void exported_names(std::vector<std::string>& out) const {
        (void)out;
    }
    // Sub-bodies of this statement (none by default). Tree walks rely on this instead of
    // re-enumerating the composite kinds, so any new statement with a body must override it or
    // walks will not descend into it.
    // Note the division of labour: `accept`/`visit` acts ACCORDING TO the kind of statement,
    // `for_each_body` DESCENDS. The two combine (see CollectGlobalsVisitor).
    virtual void for_each_body(const BodyFn& f) const {
        (void)f;
    }
    virtual ~Stmt() = default;
};
// Base for read-only visitors: any method left un-overridden is a no-op.
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
    void visit(const EnumDeclStmt&) override {
    }
    void visit(const SwitchStmt&) override {
    }
    void visit(const DoStmt&) override {
    }
};
struct Expr {
    int line = 0;
    int file_idx = 0;
    SourceLoc sloc() const {
        return {(uint16_t)file_idx, (uint16_t)line};
    }
    virtual void accept(ExprVisitor&) const = 0;
    virtual ~Expr() = default;
};

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

// 1 < x < 10 becomes (1 < x) and (x < 10), with x evaluated once.
// ops[i] is the operator character between operands[i] and operands[i+1].
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
    bool optional = false; // f?(): calls only when callable, otherwise nil
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

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
    bool is_global = false;   // true when declared with 'global', hence a global variable
    bool is_constant = false; // true when declared with 'constant', hence an immutable local
    void exported_names(std::vector<std::string>& out) const override {
        for (auto& n : names)
            out.push_back(n);
    }
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
    char op = '\0'; // '\0' = a plain assignment; '+','-','*','/','%' = compound
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
    void for_each_body(const BodyFn& f) const override {
        f(then_body);
        for (auto& ei : else_ifs)
            f(ei.body);
        f(else_body);
    }
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct WhileStmt : Stmt {
    std::unique_ptr<Expr> cond;
    std::vector<std::unique_ptr<Stmt>> body;
    void for_each_body(const BodyFn& f) const override {
        f(body);
    }
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
    void for_each_body(const BodyFn& f) const override {
        f(try_body);
        f(catch_body);
        f(else_body);
    }
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct FuncDeclStmt : Stmt {
    std::string name;
    std::vector<std::string> params;
    std::vector<std::unique_ptr<Expr>> defaults; // nullptr means no default
    bool variadic = false;
    bool is_static = false; // a class method, with no implicit self
    std::vector<std::unique_ptr<Stmt>> body;
    void exported_names(std::vector<std::string>& out) const override {
        out.push_back(name);
    }
    void for_each_body(const BodyFn& f) const override {
        f(body);
    }
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
    // key is a literal StringExpr for `ident:`, `"s":` and `["s"]:`, and an arbitrary
    // expression for computed keys `[expr]:`.
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
    std::string obj; // name of the container variable, used when obj_expr is null
    // Container as an EXPRESSION, for CHAINED targets (a.b.c, a[i][j], a.b[k]…). When set it
    // takes precedence over `obj`: the compiler evaluates it to get the map or array to index.
    // Otherwise the plain name `obj` is used.
    std::unique_ptr<Expr> obj_expr;
    std::unique_ptr<Expr> key;
    TokenType op = TokenType::EQUALS; // EQUALS, PLUS_EQUAL, MINUS_EQUAL, etc.
    std::unique_ptr<Expr> value;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct MultiAssignStmt : Stmt {
    // The targets are EXPRESSIONS, each a VarExpr or an IndexExpr — the same notion of lvalue the
    // single assignment uses (see Parser::finish_assign_from_expr). A second, poorer grammar used
    // to live here, limited to one level, so `a.b.c = 1` compiled while `a.b.c, x = 1, 2` did not.
    std::vector<std::unique_ptr<Expr>> targets;
    std::vector<std::unique_ptr<Expr>> values;
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

// for [var1,] var2 in iterable_expr
// One variable: var1 receives the primary value (the value for an array or range, the key for
// a map). Two variables: var1 is the key or index, var2 the value.
struct ForIterStmt : Stmt {
    std::string var1; // always bound: the key with two variables, the primary one with a single variable
    std::string var2; // empty = the one-variable form
    std::unique_ptr<Expr> iter_expr;
    std::vector<std::unique_ptr<Stmt>> body;
    void for_each_body(const BodyFn& f) const override {
        f(body);
    }
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct BlockStmt : Stmt {
    std::vector<std::unique_ptr<Stmt>> stmts;
    void for_each_body(const BodyFn& f) const override {
        f(stmts);
    }
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

struct DoStmt : Stmt {
    std::vector<std::unique_ptr<Stmt>> body;
    void for_each_body(const BodyFn& f) const override {
        f(body);
    }
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

// Call through an expression, the callee being anything: IndexExpr, CallExpr, VarExpr…
struct ExprCallExpr : Expr {
    std::unique_ptr<Expr> callee;
    std::vector<std::unique_ptr<Expr>> args;
    bool optional = false; // expr?(): calls only when callable, otherwise nil
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

// Method call receiver.method(args), with self passed automatically.
struct MethodCallExpr : Expr {
    std::unique_ptr<Expr> receiver; // nullptr when is_super
    std::string method;
    std::vector<std::unique_ptr<Expr>> args;
    bool is_super = false;
    bool optional = false; // obj.m?(): calls when the method is callable, gives nil when absent
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct ClassDeclStmt : Stmt {
    std::string name;
    std::string parent; // empty when there is no extends
    std::vector<std::unique_ptr<FuncDeclStmt>> methods;
    void exported_names(std::vector<std::string>& out) const override {
        out.push_back(name);
    }
    void for_each_body(const BodyFn& f) const override {
        for (auto& m : methods)
            f(m->body); // methods are FuncDeclStmt, so their bodies are exposed
    }
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

// enum Name A[=expr], B, C end — or enum obj.field A, B end, where obj_expr is set.
// An element without an explicit value gets a synthetic literal from the parser carrying the
// counter's value, so `value` is always set (see parser::enum_decl).
struct EnumItem {
    std::string name;
    std::unique_ptr<Expr> value;
};

struct EnumDeclStmt : Stmt {
    std::string name;               // a bare name (a global); otherwise the field's name
    std::unique_ptr<Expr> obj_expr; // non-null for `enum obj.field`: the target map
    std::vector<EnumItem> items;
    void exported_names(std::vector<std::string>& out) const override {
        if (!obj_expr) // `enum a.b` writes a map field, so there is no name of its own
            out.push_back(name);
    }
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
    void for_each_body(const BodyFn& f) const override {
        for (auto& arm : cases)
            f(arm.body);
        f(else_body);
    }
    void accept(StmtVisitor& v) const override {
        v.visit(*this);
    }
};

// Interpolated string "text {expr} text {expr} text".
// literals[i] precedes exprs[i], and literals.size() is always exprs.size() + 1.
struct InterpExpr : Expr {
    std::vector<std::string> literals;
    std::vector<std::unique_ptr<Expr>> exprs;
    void accept(ExprVisitor& v) const override {
        v.visit(*this);
    }
};

struct Program {
    std::vector<std::unique_ptr<Stmt>> stmts;
    std::vector<std::string> source_files;
};
