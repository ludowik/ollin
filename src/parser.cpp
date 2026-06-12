#include "parser.h"
#include <stdexcept>

Parser::Parser(std::vector<Token> tokens) : tokens(std::move(tokens)) {}

Token Parser::peek() const  { return tokens[pos]; }
Token Parser::advance()     { return tokens[pos++]; }
bool  Parser::check(TokenType t) const { return tokens[pos].type == t; }

bool Parser::match(TokenType t) {
    if (!check(t)) return false;
    advance();
    return true;
}

Token Parser::expect(TokenType t) {
    if (!check(t))
        throw std::runtime_error("unexpected token: '" + tokens[pos].lexeme +
                                 "' at line " + std::to_string(tokens[pos].line));
    return advance();
}

void Parser::skipNewlines() {
    while (check(TokenType::NEWLINE)) advance();
}

Program Parser::parse() {
    Program prog;
    while (true) {
        skipNewlines();
        if (check(TokenType::EOF_T)) break;
        if (check(TokenType::VAR))
            prog.stmts.push_back(varDecl());
        else
            prog.stmts.push_back(exprStmt());
    }
    return prog;
}

std::unique_ptr<Stmt> Parser::varDecl() {
    advance(); // consume VAR
    auto s = std::make_unique<VarDeclStmt>();
    s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    while (match(TokenType::COMMA))
        s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    expect(TokenType::EQUALS);
    s->values.push_back(expr());
    while (match(TokenType::COMMA))
        s->values.push_back(expr());
    match(TokenType::NEWLINE);
    return s;
}

std::unique_ptr<Stmt> Parser::exprStmt() {
    auto e = expr();
    match(TokenType::NEWLINE);
    return std::make_unique<ExprStmt>(std::move(e));
}

std::unique_ptr<Expr> Parser::expr() {
    return additive();
}

std::unique_ptr<Expr> Parser::additive() {
    auto left = multiplicative();
    while (check(TokenType::PLUS) || check(TokenType::MINUS)) {
        char op = advance().lexeme[0];
        auto right = multiplicative();
        left = std::make_unique<BinaryExpr>(op, std::move(left), std::move(right));
    }
    return left;
}

std::unique_ptr<Expr> Parser::multiplicative() {
    auto left = primary();
    while (check(TokenType::STAR) || check(TokenType::SLASH)) {
        char op = advance().lexeme[0];
        auto right = primary();
        left = std::make_unique<BinaryExpr>(op, std::move(left), std::move(right));
    }
    return left;
}

std::unique_ptr<Expr> Parser::primary() {
    if (check(TokenType::NUMBER)) {
        double v = std::stod(advance().lexeme);
        return std::make_unique<NumberExpr>(v);
    }
    if (check(TokenType::IDENTIFIER)) {
        std::string name = advance().lexeme;
        if (match(TokenType::LPAREN)) {
            auto call = std::make_unique<CallExpr>();
            call->callee = name;
            if (!check(TokenType::RPAREN)) {
                call->args.push_back(expr());
                while (match(TokenType::COMMA))
                    call->args.push_back(expr());
            }
            expect(TokenType::RPAREN);
            return call;
        }
        return std::make_unique<VarExpr>(name);
    }
    if (match(TokenType::LPAREN)) {
        auto e = expr();
        expect(TokenType::RPAREN);
        return e;
    }
    throw std::runtime_error("unexpected token: '" + peek().lexeme +
                             "' at line " + std::to_string(peek().line));
}
