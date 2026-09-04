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
                    std::shared_ptr<std::vector<std::string>> source_files = nullptr,
                    std::string filename = "");
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

    SourceLoc cur_loc(int line) const { return {(uint16_t)current_file_idx_, (uint16_t)line}; }

const Token& peek() const;
    const Token& advance();
    bool check(TokenType t) const;
    bool match(TokenType t);
    Token expect(TokenType t);
    void skip_comments();

    TokenType peek_next_type() const;
    TokenType peek_at(int offset) const;
    void consume_opt_comment(); // swallows an optional COMMENT

    std::unique_ptr<Stmt> parse_one_stmt();
    std::unique_ptr<Stmt> var_decl();
    std::unique_ptr<Stmt> global_decl();
    std::unique_ptr<Stmt> constant_decl();
    std::unique_ptr<Stmt> while_stmt();
    std::unique_ptr<Stmt> do_stmt();
    std::unique_ptr<Stmt> if_stmt();
    std::unique_ptr<Stmt> break_stmt();
    std::unique_ptr<Stmt> continue_stmt();
    std::unique_ptr<Stmt> try_catch_stmt();
    std::unique_ptr<Stmt> throw_stmt();
    std::unique_ptr<Stmt> func_decl_stmt();
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
    std::unique_ptr<Expr> logical();
    std::unique_ptr<Expr> logical_and();
    std::unique_ptr<Expr> bitwise_or();
    std::unique_ptr<Expr> bitwise_xor();
    std::unique_ptr<Expr> bitwise_and();
    std::unique_ptr<Expr> comparison();
    std::unique_ptr<Expr> shift();
    std::unique_ptr<Expr> additive();
    std::unique_ptr<Expr> multiplicative();
    std::unique_ptr<Expr> power();
    std::unique_ptr<Expr> unary();
    std::unique_ptr<Expr> primary();

    // Range parsing helpers
    bool looks_like_range() const;                     // scan from current pos for SEMICOLON before COMMA/RBRACKET
    std::unique_ptr<Expr> range_expr(bool incl_left); // parse rest after [ or ]
};
