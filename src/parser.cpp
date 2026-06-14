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
        throw std::runtime_error("line " + std::to_string(tokens[pos].line) +
                                 ": unexpected token '" + tokens[pos].lexeme + "'");
    return advance();
}

TokenType Parser::peekNextType() const {
    if (pos + 1 < static_cast<int>(tokens.size()))
        return tokens[pos + 1].type;
    return TokenType::EOF_T;
}

TokenType Parser::peekAt(int offset) const {
    int idx = pos + offset;
    if (idx < static_cast<int>(tokens.size())) return tokens[idx].type;
    return TokenType::EOF_T;
}

void Parser::skipNewlines() {
    while (check(TokenType::NEWLINE)) advance();
}

// absorbe un commentaire de fin de ligne optionnel puis le NEWLINE
void Parser::consumeLineEnd() {
    match(TokenType::COMMENT);
    match(TokenType::NEWLINE);
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
    if (check(TokenType::COMMENT)) {
        std::string text = advance().lexeme;
        consumeLineEnd();
        return std::make_unique<CommentStmt>(std::move(text));
    }
    if (check(TokenType::WHILE))   return whileStmt();
    if (check(TokenType::IF))      return ifStmt();
    if (check(TokenType::BREAK))   return breakStmt();
    if (check(TokenType::TRY))     return tryCatchStmt();
    if (check(TokenType::THROW))   return throwStmt();
    if (check(TokenType::FOR))     return forStmt();
    if (check(TokenType::FUNC))    return funcDeclStmt();
    if (check(TokenType::RETURN))  return returnStmt();
    if (check(TokenType::VAR))     return varDecl();
    if (check(TokenType::IDENTIFIER)) {
        TokenType nx = peekNextType();
        if (nx == TokenType::EQUALS      || nx == TokenType::PLUS_EQUAL  ||
            nx == TokenType::MINUS_EQUAL || nx == TokenType::STAR_EQUAL  ||
            nx == TokenType::SLASH_EQUAL || nx == TokenType::PERCENT_EQUAL)
            return assignStmt();
        if (nx == TokenType::DOT &&
            peekAt(2) == TokenType::IDENTIFIER) {
            // check if it's a dot assignment: m.field op= val
            TokenType after_field = peekAt(3);
            bool is_assign = (after_field == TokenType::EQUALS        ||
                              after_field == TokenType::PLUS_EQUAL     ||
                              after_field == TokenType::MINUS_EQUAL    ||
                              after_field == TokenType::STAR_EQUAL     ||
                              after_field == TokenType::SLASH_EQUAL    ||
                              after_field == TokenType::PERCENT_EQUAL);
            if (is_assign) {
                std::string obj_name = advance().lexeme; // consume IDENTIFIER
                advance(); // consume DOT
                std::string field = advance().lexeme; // consume field IDENTIFIER
                TokenType op = advance().type; // consume operator
                auto val = expr();
                consumeLineEnd();
                auto s = std::make_unique<IndexAssignStmt>();
                s->obj = obj_name;
                s->key = std::make_unique<StringExpr>(field);
                s->op  = op;
                s->value = std::move(val);
                return s;
            }
        }
        if (nx == TokenType::LBRACKET) {
            // index assignment: obj["key"] op= val
            std::string obj_name = advance().lexeme; // consume IDENTIFIER
            advance(); // consume [
            auto key = expr();
            expect(TokenType::RBRACKET);
            TokenType op = TokenType::EQUALS;
            if (check(TokenType::EQUALS)        ) { advance(); op = TokenType::EQUALS;        }
            else if (check(TokenType::PLUS_EQUAL)   ) { advance(); op = TokenType::PLUS_EQUAL;    }
            else if (check(TokenType::MINUS_EQUAL)  ) { advance(); op = TokenType::MINUS_EQUAL;   }
            else if (check(TokenType::STAR_EQUAL)   ) { advance(); op = TokenType::STAR_EQUAL;    }
            else if (check(TokenType::SLASH_EQUAL)  ) { advance(); op = TokenType::SLASH_EQUAL;   }
            else if (check(TokenType::PERCENT_EQUAL)) { advance(); op = TokenType::PERCENT_EQUAL; }
            else throw std::runtime_error("line " + std::to_string(peek().line) +
                                          ": expected assignment operator after index");
            auto val = expr();
            consumeLineEnd();
            auto s = std::make_unique<IndexAssignStmt>();
            s->obj = obj_name;
            s->key = std::move(key);
            s->op  = op;
            s->value = std::move(val);
            return s;
        }
    }
    return exprStmt();
}

// ── instructions ─────────────────────────────────────────────────────────────

std::unique_ptr<Stmt> Parser::varDecl() {
    advance();
    auto s = std::make_unique<VarDeclStmt>();
    s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    while (match(TokenType::COMMA))
        s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    if (match(TokenType::EQUALS)) {
        s->values.push_back(expr());
        while (match(TokenType::COMMA))
            s->values.push_back(expr());
    }
    // sans '=' → valeurs absentes → nil dans le compilateur
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::whileStmt() {
    advance();
    auto s = std::make_unique<WhileStmt>();
    s->cond = expr();
    consumeLineEnd();
    while (true) {
        skipNewlines();
        if (check(TokenType::END) || check(TokenType::EOF_T)) break;
        s->body.push_back(parseOneStmt());
    }
    expect(TokenType::END);
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::ifStmt() {
    advance(); // IF
    auto s = std::make_unique<IfStmt>();
    s->cond = expr();
    expect(TokenType::THEN);
    consumeLineEnd();
    while (true) {
        skipNewlines();
        if (check(TokenType::ELSE) || check(TokenType::END) || check(TokenType::EOF_T)) break;
        s->then_body.push_back(parseOneStmt());
    }
    while (check(TokenType::ELSE)) {
        advance(); // ELSE
        if (check(TokenType::IF)) {
            advance(); // IF
            ElseIfClause ei;
            ei.cond = expr();
            expect(TokenType::THEN);
            consumeLineEnd();
            while (true) {
                skipNewlines();
                if (check(TokenType::ELSE) || check(TokenType::END) || check(TokenType::EOF_T)) break;
                ei.body.push_back(parseOneStmt());
            }
            s->else_ifs.push_back(std::move(ei));
        } else {
            consumeLineEnd();
            while (true) {
                skipNewlines();
                if (check(TokenType::END) || check(TokenType::EOF_T)) break;
                s->else_body.push_back(parseOneStmt());
            }
            break;
        }
    }
    expect(TokenType::END);
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::breakStmt() {
    advance();
    consumeLineEnd();
    return std::make_unique<BreakStmt>();
}

std::unique_ptr<Stmt> Parser::throwStmt() {
    advance(); // throw
    auto s = std::make_unique<ThrowStmt>(expr());
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::tryCatchStmt() {
    advance(); // try
    auto s = std::make_unique<TryCatchStmt>();
    consumeLineEnd();
    while (true) {
        skipNewlines();
        if (check(TokenType::CATCH) || check(TokenType::EOF_T)) break;
        s->try_body.push_back(parseOneStmt());
    }
    expect(TokenType::CATCH);
    s->catch_var = expect(TokenType::IDENTIFIER).lexeme;
    consumeLineEnd();
    while (true) {
        skipNewlines();
        if (check(TokenType::ELSE) || check(TokenType::END) || check(TokenType::EOF_T)) break;
        s->catch_body.push_back(parseOneStmt());
    }
    if (match(TokenType::ELSE)) {
        consumeLineEnd();
        while (true) {
            skipNewlines();
            if (check(TokenType::END) || check(TokenType::EOF_T)) break;
            s->else_body.push_back(parseOneStmt());
        }
    }
    expect(TokenType::END);
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::funcDeclStmt() {
    advance(); // FUNC
    auto s = std::make_unique<FuncDeclStmt>();
    s->name = expect(TokenType::IDENTIFIER).lexeme;
    expect(TokenType::LPAREN);
    while (!check(TokenType::RPAREN) && !check(TokenType::EOF_T)) {
        if (check(TokenType::DOT_DOT_DOT)) { advance(); s->variadic = true; break; }
        s->params.push_back(expect(TokenType::IDENTIFIER).lexeme);
        if (match(TokenType::EQUALS))
            s->defaults.push_back(expr());
        else
            s->defaults.push_back(nullptr);
        if (!check(TokenType::RPAREN)) expect(TokenType::COMMA);
    }
    expect(TokenType::RPAREN);
    consumeLineEnd();
    while (true) {
        skipNewlines();
        if (check(TokenType::END) || check(TokenType::EOF_T)) break;
        s->body.push_back(parseOneStmt());
    }
    expect(TokenType::END);
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::returnStmt() {
    advance(); // RETURN
    auto s = std::make_unique<ReturnStmt>();
    if (!check(TokenType::NEWLINE) && !check(TokenType::COMMENT) && !check(TokenType::EOF_T)) {
        if (check(TokenType::DOT_DOT_DOT)) {
            advance(); s->spread_varargs = true;
        } else {
            s->values.push_back(expr());
            while (match(TokenType::COMMA)) {
                if (check(TokenType::DOT_DOT_DOT)) { advance(); s->spread_varargs = true; break; }
                s->values.push_back(expr());
            }
        }
    }
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::assignStmt() {
    auto s = std::make_unique<AssignStmt>();
    s->name = advance().lexeme;
    if      (match(TokenType::PLUS_EQUAL))    s->op = '+';
    else if (match(TokenType::MINUS_EQUAL))   s->op = '-';
    else if (match(TokenType::STAR_EQUAL))    s->op = '*';
    else if (match(TokenType::SLASH_EQUAL))   s->op = '/';
    else if (match(TokenType::PERCENT_EQUAL)) s->op = '%';
    else                                    { advance(); s->op = '\0'; }
    s->value = expr();
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::forStmt() {
    advance(); // FOR
    std::string first_var = expect(TokenType::IDENTIFIER).lexeme;

    if (check(TokenType::COMMA)) {
        // for k, v in map_expr
        advance(); // consume COMMA
        std::string val_var = expect(TokenType::IDENTIFIER).lexeme;
        expect(TokenType::IN);
        auto map_e = expr();
        consumeLineEnd();
        auto s = std::make_unique<ForMapStmt>();
        s->key_var  = first_var;
        s->val_var  = val_var;
        s->map_expr = std::move(map_e);
        while (true) {
            skipNewlines();
            if (check(TokenType::END) || check(TokenType::EOF_T)) break;
            s->body.push_back(parseOneStmt());
        }
        expect(TokenType::END);
        consumeLineEnd();
        return s;
    }

    auto s = std::make_unique<ForStmt>();
    s->var = first_var;
    if (match(TokenType::EQUALS)) {
        // for i=start,end[,step]
        s->start = expr();
        expect(TokenType::COMMA);
        s->end = expr();
        if (match(TokenType::COMMA)) s->step = expr();
    } else {
        // for i in start..end
        expect(TokenType::IN);
        s->start = expr();
        expect(TokenType::DOT_DOT);
        s->end = expr();
    }
    consumeLineEnd();
    while (true) {
        skipNewlines();
        if (check(TokenType::END) || check(TokenType::EOF_T)) break;
        s->body.push_back(parseOneStmt());
    }
    expect(TokenType::END);
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::exprStmt() {
    auto e = expr();
    consumeLineEnd();
    return std::make_unique<ExprStmt>(std::move(e));
}

// ── expressions ──────────────────────────────────────────────────────────────

std::unique_ptr<Expr> Parser::expr() { return logical(); }

std::unique_ptr<Expr> Parser::logical() {
    // or < and (and has higher precedence)
    auto left = logicalAnd();
    while (check(TokenType::OR)) {
        advance();
        left = std::make_unique<BinaryExpr>('|', std::move(left), logicalAnd());
    }
    return left;
}

std::unique_ptr<Expr> Parser::logicalAnd() {
    auto left = comparison();
    while (check(TokenType::AND)) {
        advance();
        left = std::make_unique<BinaryExpr>('&', std::move(left), comparison());
    }
    return left;
}

std::unique_ptr<Expr> Parser::comparison() {
    auto left = additive();
    while (check(TokenType::GREATER) || check(TokenType::LESS) ||
           check(TokenType::GREATER_EQUAL) || check(TokenType::LESS_EQUAL) ||
           check(TokenType::EQUAL_EQUAL) || check(TokenType::NOT_EQUAL)) {
        char op;
        if      (check(TokenType::EQUAL_EQUAL))  { advance(); op = '='; }
        else if (check(TokenType::GREATER_EQUAL)) { advance(); op = 'G'; }
        else if (check(TokenType::LESS_EQUAL))    { advance(); op = 'L'; }
        else if (check(TokenType::NOT_EQUAL))     { advance(); op = 'N'; }
        else op = advance().lexeme[0];
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
    auto left = unary();
    while (check(TokenType::STAR) || check(TokenType::SLASH) || check(TokenType::PERCENT)) {
        char op = advance().lexeme[0];
        left = std::make_unique<BinaryExpr>(op, std::move(left), unary());
    }
    return left;
}

std::unique_ptr<Expr> Parser::unary() {
    if (check(TokenType::MINUS)) { advance(); return std::make_unique<UnaryExpr>('-', unary()); }
    if (check(TokenType::NOT))   { advance(); return std::make_unique<UnaryExpr>('!', unary()); }
    return primary();
}

std::unique_ptr<Expr> Parser::primary() {
    if (check(TokenType::NUMBER))
        return std::make_unique<NumberExpr>(std::stod(advance().lexeme));
    if (check(TokenType::STRING))
        return std::make_unique<StringExpr>(advance().lexeme);
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
            std::unique_ptr<Expr> base = std::move(call);
            while (check(TokenType::LBRACKET) || check(TokenType::DOT)) {
                if (check(TokenType::LBRACKET)) {
                    advance(); // consume [
                    auto key = expr();
                    expect(TokenType::RBRACKET);
                    auto ie = std::make_unique<IndexExpr>();
                    ie->obj = std::move(base);
                    ie->key = std::move(key);
                    base = std::move(ie);
                } else {
                    advance(); // consume .
                    std::string field = expect(TokenType::IDENTIFIER).lexeme;
                    auto ie = std::make_unique<IndexExpr>();
                    ie->obj = std::move(base);
                    ie->key = std::make_unique<StringExpr>(field);
                    base = std::move(ie);
                }
            }
            return base;
        }
        // Plain variable — may be followed by index/dot chaining
        std::unique_ptr<Expr> base = std::make_unique<VarExpr>(name);
        while (check(TokenType::LBRACKET) || check(TokenType::DOT)) {
            if (check(TokenType::LBRACKET)) {
                advance(); // consume [
                auto key = expr();
                expect(TokenType::RBRACKET);
                auto ie = std::make_unique<IndexExpr>();
                ie->obj = std::move(base);
                ie->key = std::move(key);
                base = std::move(ie);
            } else {
                advance(); // consume .
                std::string field = expect(TokenType::IDENTIFIER).lexeme;
                auto ie = std::make_unique<IndexExpr>();
                ie->obj = std::move(base);
                ie->key = std::make_unique<StringExpr>(field);
                base = std::move(ie);
            }
        }
        return base;
    }
    if (check(TokenType::NIL))       { advance(); return std::make_unique<NilExpr>(); }
    if (check(TokenType::DOT_DOT_DOT)) { advance(); return std::make_unique<VarArgExpr>(); }
    if (check(TokenType::LBRACE)) {
        advance(); // consume {
        skipNewlines();
        auto map = std::make_unique<MapExpr>();
        while (!check(TokenType::RBRACE) && !check(TokenType::EOF_T)) {
            std::string key;
            if (check(TokenType::STRING))     key = advance().lexeme;
            else if (check(TokenType::IDENTIFIER)) key = advance().lexeme;
            else throw std::runtime_error("line " + std::to_string(peek().line) +
                     ": expected string or identifier key in map literal");
            expect(TokenType::COLON);
            auto val = expr();
            map->entries.push_back({key, std::move(val)});
            if (check(TokenType::COMMA)) advance();
            skipNewlines();
        }
        expect(TokenType::RBRACE);
        // index/dot chaining after map literal
        std::unique_ptr<Expr> base = std::move(map);
        while (check(TokenType::LBRACKET) || check(TokenType::DOT)) {
            if (check(TokenType::LBRACKET)) {
                advance();
                auto key = expr();
                expect(TokenType::RBRACKET);
                auto ie = std::make_unique<IndexExpr>();
                ie->obj = std::move(base);
                ie->key = std::move(key);
                base = std::move(ie);
            } else {
                advance(); // consume .
                std::string field = expect(TokenType::IDENTIFIER).lexeme;
                auto ie = std::make_unique<IndexExpr>();
                ie->obj = std::move(base);
                ie->key = std::make_unique<StringExpr>(field);
                base = std::move(ie);
            }
        }
        return base;
    }
    if (match(TokenType::LPAREN)) {
        auto e = expr();
        expect(TokenType::RPAREN);
        return e;
    }
    throw std::runtime_error("line " + std::to_string(peek().line) +
                             ": unexpected token '" + peek().lexeme + "'");
}
