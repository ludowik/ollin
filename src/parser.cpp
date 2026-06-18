#include "parser.h"
#include "lexer.h"
#include <fstream>
#include <sstream>
#include <stdexcept>

Parser::Parser(std::vector<Token> tokens, std::string base_dir,
               std::shared_ptr<std::unordered_set<std::string>> imported)
    : tokens(std::move(tokens)), base_dir_(std::move(base_dir)),
      imported_paths_(imported ? std::move(imported)
                               : std::make_shared<std::unordered_set<std::string>>()) {}

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
    while (check(TokenType::NEWLINE) || check(TokenType::COMMENT)) advance();
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
    if (check(TokenType::BREAK))    return breakStmt();
    if (check(TokenType::CONTINUE)) return continueStmt();
    if (check(TokenType::TRY))     return tryCatchStmt();
    if (check(TokenType::THROW))   return throwStmt();
    if (check(TokenType::FOR))     return forStmt();
    if (check(TokenType::IMPORT))  return importStmt();
    if (check(TokenType::CLASS))   return classDecl();
    if (check(TokenType::FUNC))    return funcDeclStmt();
    if (check(TokenType::RETURN))  return returnStmt();
    if (check(TokenType::VAR))      return varDecl();
    if (check(TokenType::GLOBAL))   return globalDecl();
    if (check(TokenType::CONSTANT)) return constantDecl();
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
    int line = peek().line;
    advance();
    auto s = std::make_unique<VarDeclStmt>();
    s->line = line;
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

std::unique_ptr<Stmt> Parser::globalDecl() {
    int line = peek().line;
    advance(); // consume 'global'
    auto s = std::make_unique<VarDeclStmt>();
    s->is_global = true;
    s->line = line;
    s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    while (match(TokenType::COMMA))
        s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    if (match(TokenType::EQUALS)) {
        s->values.push_back(expr());
        while (match(TokenType::COMMA))
            s->values.push_back(expr());
    }
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::constantDecl() {
    int line = peek().line;
    advance(); // consume 'constant'
    auto s = std::make_unique<VarDeclStmt>();
    s->is_constant = true;
    s->line = line;
    s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    while (match(TokenType::COMMA))
        s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    if (!check(TokenType::EQUALS))
        throw std::runtime_error("line " + std::to_string(line)
                                 + ": constant '" + s->names[0] + "' must be initialized");
    advance(); // consume '='
    s->values.push_back(expr());
    while (match(TokenType::COMMA))
        s->values.push_back(expr());
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::whileStmt() {
    int line = peek().line;
    advance();
    auto s = std::make_unique<WhileStmt>();
    s->line = line;
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
    int line = peek().line;
    advance(); // IF
    auto s = std::make_unique<IfStmt>();
    s->line = line;
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
    int line = peek().line;
    advance();
    consumeLineEnd();
    auto s = std::make_unique<BreakStmt>();
    s->line = line;
    return s;
}

std::unique_ptr<Stmt> Parser::continueStmt() {
    int line = peek().line;
    advance();
    consumeLineEnd();
    auto s = std::make_unique<ContinueStmt>();
    s->line = line;
    return s;
}

std::unique_ptr<Stmt> Parser::throwStmt() {
    int line = peek().line;
    advance(); // throw
    auto s = std::make_unique<ThrowStmt>(expr());
    s->line = line;
    consumeLineEnd();
    return s;
}

std::unique_ptr<Stmt> Parser::tryCatchStmt() {
    int line = peek().line;
    advance(); // try
    auto s = std::make_unique<TryCatchStmt>();
    s->line = line;
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
    int line = peek().line;
    advance(); // FUNC
    auto s = std::make_unique<FuncDeclStmt>();
    s->line = line;
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
    int line = peek().line;
    advance(); // RETURN
    auto s = std::make_unique<ReturnStmt>();
    s->line = line;
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
    int line = peek().line;
    auto s = std::make_unique<AssignStmt>();
    s->line = line;
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
    int line = peek().line;
    advance(); // FOR
    std::string first_var = expect(TokenType::IDENTIFIER).lexeme;

    if (match(TokenType::EQUALS)) {
        // for i=start,end[,step]  →  désucré en  for i in [start;end[;step]]
        auto range = std::make_unique<RangeExpr>();
        range->line      = line;
        range->incl_left = true;
        range->incl_right = true;
        range->start = expr();
        expect(TokenType::COMMA);
        range->end = expr();
        if (match(TokenType::COMMA)) range->step = expr();
        consumeLineEnd();
        auto s = std::make_unique<ForIterStmt>();
        s->line      = line;
        s->var1      = first_var;
        s->iter_expr = std::move(range);
        while (true) {
            skipNewlines();
            if (check(TokenType::END) || check(TokenType::EOF_T)) break;
            s->body.push_back(parseOneStmt());
        }
        expect(TokenType::END);
        consumeLineEnd();
        return s;
    }

    // for var1[, var2] in expr
    std::string var2;
    if (check(TokenType::COMMA)) {
        advance();
        var2 = expect(TokenType::IDENTIFIER).lexeme;
    }
    expect(TokenType::IN);
    auto iter_e = expr();
    consumeLineEnd();
    auto s = std::make_unique<ForIterStmt>();
    s->line      = line;
    s->var1      = first_var;
    s->var2      = var2;
    s->iter_expr = std::move(iter_e);
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
    int line = peek().line;
    auto e = expr();
    consumeLineEnd();
    auto s = std::make_unique<ExprStmt>(std::move(e));
    s->line = line;
    return s;
}

// ── expressions ──────────────────────────────────────────────────────────────

std::unique_ptr<Expr> Parser::expr() { return logical(); }

std::unique_ptr<Expr> Parser::logical() {
    auto left = logicalAnd();
    while (true) {
        if (paren_depth_ > 0) skipNewlines();
        if (!check(TokenType::OR)) break;
        advance();
        if (paren_depth_ > 0) skipNewlines();
        left = std::make_unique<BinaryExpr>('|', std::move(left), logicalAnd());
    }
    return left;
}

std::unique_ptr<Expr> Parser::logicalAnd() {
    auto left = bitwiseOr();
    while (true) {
        if (paren_depth_ > 0) skipNewlines();
        if (!check(TokenType::AND)) break;
        advance();
        if (paren_depth_ > 0) skipNewlines();
        left = std::make_unique<BinaryExpr>('&', std::move(left), bitwiseOr());
    }
    return left;
}

std::unique_ptr<Expr> Parser::bitwiseOr() {
    auto left = bitwiseXor();
    while (true) {
        if (paren_depth_ > 0) skipNewlines();
        if (!check(TokenType::PIPE)) break;
        advance();
        if (paren_depth_ > 0) skipNewlines();
        left = std::make_unique<BinaryExpr>('o', std::move(left), bitwiseXor());
    }
    return left;
}

std::unique_ptr<Expr> Parser::bitwiseXor() {
    auto left = bitwiseAnd();
    while (true) {
        if (paren_depth_ > 0) skipNewlines();
        if (!check(TokenType::CARET)) break;
        advance();
        if (paren_depth_ > 0) skipNewlines();
        left = std::make_unique<BinaryExpr>('x', std::move(left), bitwiseAnd());
    }
    return left;
}

std::unique_ptr<Expr> Parser::bitwiseAnd() {
    auto left = comparison();
    while (true) {
        if (paren_depth_ > 0) skipNewlines();
        if (!check(TokenType::AMP)) break;
        advance();
        if (paren_depth_ > 0) skipNewlines();
        left = std::make_unique<BinaryExpr>('b', std::move(left), comparison());
    }
    return left;
}

std::unique_ptr<Expr> Parser::comparison() {
    auto left = shift();
    while (true) {
        if (paren_depth_ > 0) skipNewlines();
        if (!check(TokenType::GREATER) && !check(TokenType::LESS) &&
            !check(TokenType::GREATER_EQUAL) && !check(TokenType::LESS_EQUAL) &&
            !check(TokenType::EQUAL_EQUAL) && !check(TokenType::NOT_EQUAL)) break;
        char op;
        if      (check(TokenType::EQUAL_EQUAL))   { advance(); op = '='; }
        else if (check(TokenType::GREATER_EQUAL))  { advance(); op = 'G'; }
        else if (check(TokenType::LESS_EQUAL))     { advance(); op = 'L'; }
        else if (check(TokenType::NOT_EQUAL))      { advance(); op = 'N'; }
        else op = advance().lexeme[0];
        if (paren_depth_ > 0) skipNewlines();
        left = std::make_unique<BinaryExpr>(op, std::move(left), additive());
    }
    return left;
}

std::unique_ptr<Expr> Parser::shift() {
    auto left = additive();
    while (true) {
        if (paren_depth_ > 0) skipNewlines();
        if (!check(TokenType::LSHIFT) && !check(TokenType::RSHIFT)) break;
        char op = check(TokenType::LSHIFT) ? 'l' : 'r';
        advance();
        if (paren_depth_ > 0) skipNewlines();
        left = std::make_unique<BinaryExpr>(op, std::move(left), additive());
    }
    return left;
}

std::unique_ptr<Expr> Parser::additive() {
    auto left = multiplicative();
    while (true) {
        if (paren_depth_ > 0) skipNewlines();
        if (!check(TokenType::PLUS) && !check(TokenType::MINUS)) break;
        char op = advance().lexeme[0];
        if (paren_depth_ > 0) skipNewlines();
        left = std::make_unique<BinaryExpr>(op, std::move(left), multiplicative());
    }
    return left;
}

std::unique_ptr<Expr> Parser::multiplicative() {
    auto left = unary();
    while (true) {
        if (paren_depth_ > 0) skipNewlines();
        if (!check(TokenType::STAR) && !check(TokenType::SLASH) && !check(TokenType::PERCENT)) break;
        char op = advance().lexeme[0];
        if (paren_depth_ > 0) skipNewlines();
        left = std::make_unique<BinaryExpr>(op, std::move(left), unary());
    }
    return left;
}

std::unique_ptr<Expr> Parser::unary() {
    if (check(TokenType::MINUS)) { advance(); return std::make_unique<UnaryExpr>('-', unary()); }
    if (check(TokenType::NOT))   { advance(); return std::make_unique<UnaryExpr>('!', unary()); }
    if (check(TokenType::TILDE)) { advance(); return std::make_unique<UnaryExpr>('~', unary()); }
    return primary();
}

std::unique_ptr<Expr> Parser::parsePostfix(std::unique_ptr<Expr> base) {
    while (check(TokenType::LBRACKET) || check(TokenType::DOT) || check(TokenType::LPAREN)) {
        if (check(TokenType::LBRACKET)) {
            advance();
            auto key = expr();
            expect(TokenType::RBRACKET);
            auto ie = std::make_unique<IndexExpr>();
            ie->obj = std::move(base);
            ie->key = std::move(key);
            base = std::move(ie);
        } else if (check(TokenType::DOT)) {
            advance();
            std::string field = expect(TokenType::IDENTIFIER).lexeme;
            if (check(TokenType::LPAREN)) {
                advance(); // consume LPAREN
                auto mc = std::make_unique<MethodCallExpr>();
                mc->receiver = std::move(base);
                mc->method = field;
                mc->is_super = false;
                if (!check(TokenType::RPAREN)) {
                    mc->args.push_back(expr());
                    while (match(TokenType::COMMA))
                        mc->args.push_back(expr());
                }
                expect(TokenType::RPAREN);
                base = std::move(mc);
            } else {
                auto ie = std::make_unique<IndexExpr>();
                ie->obj = std::move(base);
                ie->key = std::make_unique<StringExpr>(field);
                base = std::move(ie);
            }
        } else { // LPAREN
            advance();
            auto call = std::make_unique<ExprCallExpr>();
            call->callee = std::move(base);
            if (!check(TokenType::RPAREN)) {
                call->args.push_back(expr());
                while (match(TokenType::COMMA))
                    call->args.push_back(expr());
            }
            expect(TokenType::RPAREN);
            base = std::move(call);
        }
    }
    return base;
}

// ── Range helpers ─────────────────────────────────────────────────────────────

// Scan forward from current position looking for SEMICOLON at depth 0 before
// COMMA or RBRACKET at depth 0. Returns true if this looks like a range.
bool Parser::looksLikeRange() const {
    int depth = 0;
    for (int i = pos; i < (int)tokens.size(); ++i) {
        TokenType t = tokens[i].type;
        if (t == TokenType::LBRACKET || t == TokenType::LPAREN || t == TokenType::LBRACE) {
            depth++;
        } else if (t == TokenType::RBRACKET || t == TokenType::RPAREN || t == TokenType::RBRACE) {
            if (depth == 0) return false;  // closing bracket at depth 0 = end of array
            depth--;
        } else if (depth == 0) {
            if (t == TokenType::SEMICOLON) return true;
            if (t == TokenType::COMMA) return false;
            if (t == TokenType::NEWLINE || t == TokenType::EOF_T) return false;
        }
    }
    return false;
}

// Parse range after the opening bracket character has been consumed.
// incl_left=true  means we saw '[' (inclusive left)
// incl_left=false means we saw ']' (exclusive left = open left)
std::unique_ptr<Expr> Parser::rangeExpr(bool incl_left) {
    auto node = std::make_unique<RangeExpr>();
    node->incl_left = incl_left;

    // Parse start expression
    node->start = expr();

    // Expect SEMICOLON separator
    expect(TokenType::SEMICOLON);

    // Parse end expression
    node->end = expr();

    // Optional step: if next is SEMICOLON
    if (match(TokenType::SEMICOLON)) {
        node->step = expr();
    }

    // Closing bracket: ] = incl_right, [ = excl_right
    if (check(TokenType::RBRACKET)) {
        advance();
        node->incl_right = true;
    } else if (check(TokenType::LBRACKET)) {
        advance();
        node->incl_right = false;
    } else {
        throw std::runtime_error("line " + std::to_string(peek().line) +
                                 ": expected ']' or '[' to close range");
    }

    // If open-left, adjust start: start += step (or 1 if no step)
    // We do this at the AST level by wrapping: start = start + step_expr
    if (!incl_left) {
        std::unique_ptr<Expr> step_expr;
        if (node->step) {
            // clone step - we just copy the node since it'll be owned by BinaryExpr
            // We can't clone easily so instead store in a temp and recreate
            // Actually: we need start = start + step. Let's build a BinaryExpr
            // But step is unique_ptr already stored... we need a second reference.
            // Simplest: compute at runtime. We'll use a special flag or just adjust here.
            // Since we can't clone unique_ptr, let's just use a NumberExpr(1) as approximation
            // for the open-left adjustment and apply the real step in the VM.
            // Actually: the cleanest approach is to do the adjustment in the compiler.
            // The compiler will handle incl_left=false by adding step.
            // So we don't need to adjust here - let the compiler handle it.
        }
        (void)step_expr;
    }

    return node;
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
        // super.method(args) — appel de la méthode parente avec le self courant
        if (name == "super") {
            expect(TokenType::DOT);
            std::string method_name = expect(TokenType::IDENTIFIER).lexeme;
            if (!check(TokenType::LPAREN))
                throw std::runtime_error("line " + std::to_string(peek().line) +
                                         ": super: seuls les appels de méthode sont supportés");
            advance(); // LPAREN
            auto mc = std::make_unique<MethodCallExpr>();
            mc->receiver = nullptr;
            mc->method = method_name;
            mc->is_super = true;
            if (!check(TokenType::RPAREN)) {
                mc->args.push_back(expr());
                while (match(TokenType::COMMA))
                    mc->args.push_back(expr());
            }
            expect(TokenType::RPAREN);
            return parsePostfix(std::move(mc));
        }
        if (match(TokenType::LPAREN)) {
            auto call = std::make_unique<CallExpr>();
            call->callee = name;
            if (!check(TokenType::RPAREN)) {
                call->args.push_back(expr());
                while (match(TokenType::COMMA))
                    call->args.push_back(expr());
            }
            expect(TokenType::RPAREN);
            return parsePostfix(std::move(call));
        }
        // Plain variable — may be followed by postfix chaining
        return parsePostfix(std::make_unique<VarExpr>(name));
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
        return parsePostfix(std::move(map));
    }
    if (check(TokenType::LBRACKET)) {
        advance(); // consume [
        // Check if this is a range [a;b] or array [a,b,c]
        if (looksLikeRange()) {
            return rangeExpr(true);  // incl_left=true
        }
        skipNewlines();
        auto arr = std::make_unique<ArrayExpr>();
        while (!check(TokenType::RBRACKET) && !check(TokenType::EOF_T)) {
            arr->elements.push_back(expr());
            if (check(TokenType::COMMA)) advance();
            skipNewlines();
        }
        expect(TokenType::RBRACKET);
        return parsePostfix(std::move(arr));
    }
    if (check(TokenType::RBRACKET)) {
        // Open-left range: ]a;b]  or  ]a;b[
        advance(); // consume ]
        return rangeExpr(false);  // incl_left=false
    }
    if (match(TokenType::LPAREN)) {
        paren_depth_++;
        skipNewlines();
        auto e = expr();
        skipNewlines();
        expect(TokenType::RPAREN);
        paren_depth_--;
        return e;
    }
    throw std::runtime_error("line " + std::to_string(peek().line) +
                             ": unexpected token '" + peek().lexeme + "'");
}

std::unique_ptr<Stmt> Parser::classDecl() {
    int line = peek().line;
    advance(); // CLASS
    auto s = std::make_unique<ClassDeclStmt>();
    s->line = line;
    s->name = expect(TokenType::IDENTIFIER).lexeme;
    if (check(TokenType::EXTENDS)) {
        advance();
        s->parent = expect(TokenType::IDENTIFIER).lexeme;
    }
    consumeLineEnd();
    while (true) {
        skipNewlines();
        if (check(TokenType::END) || check(TokenType::EOF_T)) break;
        if (!check(TokenType::FUNC))
            throw std::runtime_error("line " + std::to_string(peek().line) +
                                     ": expected 'func' inside class body");
        s->methods.push_back(std::unique_ptr<FuncDeclStmt>(
            static_cast<FuncDeclStmt*>(funcDeclStmt().release())));
    }
    expect(TokenType::END);
    consumeLineEnd();
    return s;
}

static std::vector<std::string> collectTopLevelNames(
    const std::vector<std::unique_ptr<Stmt>>& stmts)
{
    std::vector<std::string> names;
    for (auto& s : stmts) {
        if (auto* v = dynamic_cast<const VarDeclStmt*>(s.get()))
            for (auto& n : v->names) names.push_back(n);
        else if (auto* f = dynamic_cast<const FuncDeclStmt*>(s.get()))
            names.push_back(f->name);
    }
    return names;
}

std::unique_ptr<Stmt> Parser::importStmt() {
    advance();  // consomme 'import'
    Token path_tok = expect(TokenType::STRING);
    std::string path = path_tok.lexeme;
    if (path.size() < 3 || path.substr(path.size() - 3) != ".ol")
        path += ".ol";

    std::string alias;
    if (check(TokenType::AS)) {
        advance();
        alias = expect(TokenType::IDENTIFIER).lexeme;
    }
    consumeLineEnd();

    // Résoudre le chemin par rapport au répertoire du script courant
    std::string resolved = (!path.empty() && (path[0] == '/' ||
                            (path.size() > 1 && path[1] == ':')))
                           ? path : base_dir_ + path;

    auto block = std::make_unique<BlockStmt>();

    // Protection contre les imports circulaires
    if (imported_paths_->count(resolved)) {
        if (!alias.empty()) {
            // Alias demandé mais déjà importé : créer une map vide
            auto vd = std::make_unique<VarDeclStmt>();
            vd->names.push_back(alias);
            vd->values.push_back(std::make_unique<MapExpr>());
            block->stmts.push_back(std::move(vd));
        }
        return block;
    }
    imported_paths_->insert(resolved);

    // Lire et parser le fichier importé
    std::ifstream f(resolved);
    if (!f) throw std::runtime_error("import: cannot open '" + resolved + "'");
    std::ostringstream ss;
    ss << f.rdbuf();

    auto sep2 = resolved.find_last_of("/\\");
    std::string sub_dir = (sep2 != std::string::npos)
                          ? resolved.substr(0, sep2 + 1) : base_dir_;

    Parser sub_parser(Lexer(ss.str()).tokenize(), sub_dir, imported_paths_);
    Program sub_prog = sub_parser.parse();

    if (alias.empty()) {
        // import flat : injecter directement toutes les instructions
        for (auto& s : sub_prog.stmts)
            block->stmts.push_back(std::move(s));
    } else {
        // import as name : var name = {}; <stmts>; name[k] = k pour chaque nom top-level
        auto top_names = collectTopLevelNames(sub_prog.stmts);

        auto vd = std::make_unique<VarDeclStmt>();
        vd->names.push_back(alias);
        vd->values.push_back(std::make_unique<MapExpr>());
        block->stmts.push_back(std::move(vd));

        for (auto& s : sub_prog.stmts)
            block->stmts.push_back(std::move(s));

        for (auto& tname : top_names) {
            auto ia = std::make_unique<IndexAssignStmt>();
            ia->obj   = alias;
            ia->key   = std::make_unique<StringExpr>(tname);
            ia->op    = TokenType::EQUALS;
            ia->value = std::make_unique<VarExpr>(tname);
            block->stmts.push_back(std::move(ia));
        }
    }
    return block;
}
