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

TokenType Parser::peekNextType() const {
    if (pos + 1 < static_cast<int>(tokens.size()))
        return tokens[pos + 1].type;
    return TokenType::EOF_T;
}

void Parser::skipNewlines() {
    while (check(TokenType::NEWLINE)) advance();
}

// ── entrée principale ────────────────────────────────────────────────────────

Program Parser::parse() {
    Program prog;
    while (true) {
        skipNewlines();
        if (check(TokenType::EOF_T)) break;
        prog.stmts.push_back(parseOneStmt());
    }
    return prog;
}

// ── dispatch ─────────────────────────────────────────────────────────────────

std::unique_ptr<Stmt> Parser::parseOneStmt() {
    if (check(TokenType::WHILE))   return whileStmt();
    if (check(TokenType::IF))      return ifStmt();
    if (check(TokenType::BREAK))   return breakStmt();
    if (check(TokenType::VAR))     return varDecl();
    if (check(TokenType::IDENTIFIER) && peekNextType() == TokenType::PLUS_EQUAL)
        return assignStmt();
    return exprStmt();
}

// ── instructions ─────────────────────────────────────────────────────────────

std::unique_ptr<Stmt> Parser::varDecl() {
    advance(); // consomme VAR
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

std::unique_ptr<Stmt> Parser::whileStmt() {
    advance(); // consomme WHILE
    auto s = std::make_unique<WhileStmt>();
    s->cond = expr();
    match(TokenType::NEWLINE);
    while (true) {
        skipNewlines();
        if (check(TokenType::END) || check(TokenType::EOF_T)) break;
        s->body.push_back(parseOneStmt());
    }
    expect(TokenType::END);
    match(TokenType::NEWLINE);
    return s;
}

std::unique_ptr<Stmt> Parser::ifStmt() {
    advance(); // consomme IF
    auto s = std::make_unique<IfStmt>();
    s->cond = expr();
    s->then = parseOneStmt(); // instruction inline, pas de saut de ligne
    return s;
}

std::unique_ptr<Stmt> Parser::breakStmt() {
    advance(); // consomme BREAK
    match(TokenType::NEWLINE);
    return std::make_unique<BreakStmt>();
}

std::unique_ptr<Stmt> Parser::assignStmt() {
    auto s = std::make_unique<AssignStmt>();
    s->name = advance().lexeme; // IDENTIFIER
    if (match(TokenType::PLUS_EQUAL)) s->op = '+';
    else { advance(); s->op = '\0'; } // EQUALS
    s->value = expr();
    match(TokenType::NEWLINE);
    return s;
}

std::unique_ptr<Stmt> Parser::exprStmt() {
    auto e = expr();
    match(TokenType::NEWLINE);
    return std::make_unique<ExprStmt>(std::move(e));
}

// ── expressions ──────────────────────────────────────────────────────────────

std::unique_ptr<Expr> Parser::expr() { return comparison(); }

std::unique_ptr<Expr> Parser::comparison() {
    auto left = additive();
    while (check(TokenType::GREATER) || check(TokenType::LESS)) {
        char op = advance().lexeme[0];
        left = std::make_unique<BinaryExpr>(op, std::move(left), additive());
    }
    return left;
}

std::unique_ptr<Expr> Parser::additive() {
    auto left = multiplicative();
    while (check(TokenType::PLUS) || check(TokenType::MINUS)) {
        char op = advance().lexeme[0];
        left = std::make_unique<BinaryExpr>(op, std::move(left), multiplicative());
    }
    return left;
}

std::unique_ptr<Expr> Parser::multiplicative() {
    auto left = primary();
    while (check(TokenType::STAR) || check(TokenType::SLASH)) {
        char op = advance().lexeme[0];
        left = std::make_unique<BinaryExpr>(op, std::move(left), primary());
    }
    return left;
}

std::unique_ptr<Expr> Parser::primary() {
    if (check(TokenType::NUMBER))
        return std::make_unique<NumberExpr>(std::stod(advance().lexeme));
    if (check(TokenType::TRUE))  { advance(); return std::make_unique<BoolExpr>(true);  }
    if (check(TokenType::FALSE)) { advance(); return std::make_unique<BoolExpr>(false); }
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
