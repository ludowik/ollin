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
                    std::shared_ptr<std::unordered_map<std::string, std::vector<std::string>>> module_names = nullptr,
                    std::shared_ptr<std::vector<std::string>> source_files = nullptr);
    Program parse();

  private:
    std::vector<Token> tokens;
    int pos = 0;
    std::string base_dir_;
    std::shared_ptr<std::unordered_set<std::string>> imported_paths_;
    // Shared cache from resolved path to exported top-level names, so an aliased import can build
    // its map even when the module was already imported (dedup is not a cycle).
    std::shared_ptr<std::unordered_map<std::string, std::vector<std::string>>> module_names_;
    std::shared_ptr<std::vector<std::string>> source_files_;
    int current_file_idx_ = 0;
    int depth_ = 0; // the recursion depth, guarding against a stack overflow

    SourceLoc cur_loc(int line) const {
        return {(uint16_t)current_file_idx_, (uint16_t)line};
    }

    const Token& peek() const;
    const Token& advance();
    bool check(TokenType t) const;
    bool match(TokenType t);
    const Token& expect(TokenType t);
    // A plain NAME: an identifier, or a keyword used where no keyword can be meant.
    bool at_name() const;
    std::string expect_name(const char* what);
    // An optional method call, 'f?()': a '?' is only that when a '(' follows it.
    bool at_optional_call() const;
    void skip_comments();

    // Every refusal goes through one of these, so a message always carries its location.
    [[noreturn]] void fail(const std::string& msg) const;
    [[noreturn]] void fail_at(int line, const std::string& msg) const;

    TokenType peek_next_type() const;
    void consume_opt_comment(); // swallows an optional COMMENT

    // A token that ends a block, whichever block it is.
    bool at_block_terminator() const;
    // Statements up to one of `stops` (EOF always stops), comments skipped. Thirteen block
    // bodies share it — an if has three — so the rule lives in one place.
    void parse_body_until(std::vector<std::unique_ptr<Stmt>>& out, std::initializer_list<TokenType> stops);
    // "(" [ params ] ")", shared by 'func name(...)' and by an anonymous 'func(...)'.
    void parse_params(std::vector<std::string>& params, std::vector<std::unique_ptr<Expr>>& defaults, bool& variadic);
    // A comma-separated expression list, up to but excluding its terminator.
    void parse_expr_list(std::vector<std::unique_ptr<Expr>>& out);
    // The arguments of a call whose '(' is already consumed, closing ')' included.
    void parse_call_args(std::vector<std::unique_ptr<Expr>>& out);
    // A name, then the fields of a path: IDENT { "." NAME }.
    void parse_field_path(std::vector<std::string>& path);
    // The comma between two items of a literal: mandatory, except right before `closing`.
    void expect_separator(TokenType closing, const char* what);

    std::unique_ptr<Stmt> parse_one_stmt();
    // var / global / const: one rule, the keyword only choosing the flags.
    std::unique_ptr<Stmt> decl_stmt(bool is_global, bool is_constant);
    std::unique_ptr<Stmt> while_stmt();
    std::unique_ptr<Stmt> do_stmt();
    std::unique_ptr<Stmt> if_stmt();
    std::unique_ptr<Stmt> break_stmt();
    std::unique_ptr<Stmt> continue_stmt();
    std::unique_ptr<Stmt> try_catch_stmt();
    std::unique_ptr<Stmt> throw_stmt();
    std::unique_ptr<Stmt> func_decl_stmt();
    // 'func name(...)' alone: what a class body accepts, the 'func obj.field(...)' form being
    // a statement-level desugaring. Returning the exact type spares the caller a cast.
    std::unique_ptr<FuncDeclStmt> func_decl_named();
    // The signature and body, the name being already read.
    std::unique_ptr<FuncDeclStmt> finish_func_decl(int line, std::string name);
    std::unique_ptr<Stmt> return_stmt();
    std::unique_ptr<Stmt> multi_assign_stmt();
    std::unique_ptr<Stmt> expr_stmt();
    // Builds the assignment statement from an already parsed target: a VarExpr becomes an
    // AssignStmt, an IndexExpr a chained IndexAssignStmt. Any other form is rejected with
    // "invalid assignment target".
    std::unique_ptr<Stmt> finish_assign_from_expr(std::unique_ptr<Expr> target, int line);
    std::unique_ptr<Stmt> for_stmt();
    std::unique_ptr<Stmt> import_stmt();
    std::unique_ptr<Stmt> class_decl();
    std::unique_ptr<Stmt> enum_decl();
    std::unique_ptr<Expr> ref_expr();
    std::unique_ptr<Stmt> switch_stmt();

    std::unique_ptr<Expr> parse_postfix(std::unique_ptr<Expr> base);

    std::unique_ptr<Expr> expr();
    // The left-associative binary levels are ONE loop over a table of precedences (see
    // parser.cpp): they differed only by their operators. The comparison sits between the two
    // tables, being chainable (a < b < c) and therefore a shape of its own.
    std::unique_ptr<Expr> binary_level(int level);
    std::unique_ptr<Expr> comparison();
    std::unique_ptr<Expr> power();
    std::unique_ptr<Expr> unary();
    std::unique_ptr<Expr> primary();

    // Range parsing helpers
    bool looks_like_range() const;                    // scan from current pos for SEMICOLON before COMMA/RBRACKET
    std::unique_ptr<Expr> range_expr(bool incl_left); // parse rest after [ or ]
};
