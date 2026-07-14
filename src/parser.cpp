#include "parser.h"
#include "lexer.h"
#include "source_registry.h"
#include <fstream>
#include <sstream>
#include <stdexcept>

Parser::Parser(std::vector<Token> tokens, std::string base_dir,
               std::shared_ptr<std::unordered_set<std::string>> imported,
               std::shared_ptr<std::unordered_map<std::string, std::vector<std::string>>> module_names)
    : tokens(std::move(tokens)), base_dir_(std::move(base_dir)),
      imported_paths_(imported ? std::move(imported) : std::make_shared<std::unordered_set<std::string>>()),
      module_names_(module_names ? std::move(module_names)
                                 : std::make_shared<std::unordered_map<std::string, std::vector<std::string>>>()) {
}

const Token& Parser::peek() const {
    return tokens[pos];
}
const Token& Parser::advance() {
    return tokens[pos++];
}
bool Parser::check(TokenType t) const {
    return tokens[pos].type == t;
}

bool Parser::match(TokenType t) {
    if (!check(t))
        return false;
    advance();
    return true;
}

Token Parser::expect(TokenType t) {
    if (!check(t))
        throw std::runtime_error("line " + std::to_string(tokens[pos].line) + ": unexpected token '" +
                                 tokens[pos].lexeme + "'");
    return advance();
}

TokenType Parser::peekNextType() const {
    if (pos + 1 < static_cast<int>(tokens.size()))
        return tokens[pos + 1].type;
    return TokenType::EOF_T;
}

TokenType Parser::peekAt(int offset) const {
    int idx = pos + offset;
    if (idx < static_cast<int>(tokens.size()))
        return tokens[idx].type;
    return TokenType::EOF_T;
}

void Parser::skipComments() {
    while (check(TokenType::COMMENT))
        advance();
}

// Absorbe un COMMENT optionnel en fin d'instruction. (Les instructions sont
// séparées par des retours à la ligne, non tokenisés ; il n'y a pas d'ASI.)
void Parser::consumeOptComment() {
    match(TokenType::COMMENT);
}

// Garde anti-débordement de pile : la descente récursive (parenthèses, appels,
// blocs imbriqués) pouvait faire planter le processus sur une entrée très
// imbriquée. On borne la profondeur et on lève une erreur propre à la place.
namespace {
struct DepthGuard {
    int& d;
    DepthGuard(int& depth, int line) : d(depth) {
        if (++d > 256)
            throw std::runtime_error("line " + std::to_string(line) + ": nesting too deep");
    }
    ~DepthGuard() {
        --d;
    }
};
} // namespace

// ── entrée principale ────────────────────────────────────────────────────────

Program Parser::parse() {
    Program prog;
    while (true) {
        skipComments();
        if (check(TokenType::EOF_T))
            break;
        prog.stmts.push_back(parseOneStmt());
    }
    return prog;
}

// ── dispatch ─────────────────────────────────────────────────────────────────

static bool isAssignOp(TokenType t) {
    return t == TokenType::EQUALS || t == TokenType::PLUS_EQUAL || t == TokenType::MINUS_EQUAL ||
           t == TokenType::STAR_EQUAL || t == TokenType::SLASH_EQUAL || t == TokenType::PERCENT_EQUAL;
}

std::unique_ptr<Stmt> Parser::parseOneStmt() {
    DepthGuard guard(depth_, peek().line);
    switch (peek().type) {
    case TokenType::COMMENT: {
        std::string text = advance().lexeme;
        consumeOptComment();
        return std::make_unique<CommentStmt>(std::move(text));
    }
    case TokenType::SEMICOLON:
        // ';' n'est valide qu'à l'intérieur d'un range [a;b] (consommé par
        // rangeExpr). Au niveau instruction, c'est une erreur — message clair.
        throw std::runtime_error("line " + std::to_string(peek().line) +
                                 ": ';' is not valid syntax — statements are terminated by newlines");
    case TokenType::WHILE:    return whileStmt();
    case TokenType::IF:       return ifStmt();
    case TokenType::BREAK:    return breakStmt();
    case TokenType::CONTINUE: return continueStmt();
    case TokenType::TRY:      return tryCatchStmt();
    case TokenType::THROW:    return throwStmt();
    case TokenType::FOR:      return forStmt();
    case TokenType::IMPORT:   return importStmt();
    case TokenType::CLASS:    return classDecl();
    case TokenType::SWITCH:   return switchStmt();
    case TokenType::FUNC:     return funcDeclStmt();
    case TokenType::RETURN:   return returnStmt();
    case TokenType::VAR:      return varDecl();
    case TokenType::GLOBAL:   return globalDecl();
    case TokenType::CONSTANT: return constantDecl();
    case TokenType::IDENTIFIER: {
        // Une instruction débutant par un identifiant est soit une affectation
        // (simple, indexée, ou chaînée), soit une multi-affectation, soit une
        // instruction-expression. On parse une expression : selon ce qui suit
        // (opérateur d'affectation, virgule, ou rien) on décide. La cible d'une
        // affectation doit être une lvalue (VarExpr ou IndexExpr) — cela couvre
        // uniformément a=, a.b=, a[i]=, a.b.c=, a[i][j]=, a.b[k]= (cf. grammaire).
        int line = peek().line;
        int saved = pos;
        auto e = expr();
        if (isAssignOp(peek().type))
            return finishAssignFromExpr(std::move(e), line);
        if (check(TokenType::COMMA)) {
            pos = saved; // multi-affectation : re-parse via multiAssignStmt (LValue)
            return multiAssignStmt();
        }
        consumeOptComment();
        auto st = std::make_unique<ExprStmt>(std::move(e));
        st->line = line;
        return st;
    }
    default:
        break;
    }
    return exprStmt();
}

// Transforme une cible déjà parsée + l'opérateur d'affectation courant en
// instruction. VarExpr → AssignStmt ; IndexExpr (a.b, a[i], et chaînes) →
// IndexAssignStmt avec le conteneur en obj_expr.
std::unique_ptr<Stmt> Parser::finishAssignFromExpr(std::unique_ptr<Expr> target, int line) {
    TokenType opt = advance().type; // opérateur d'affectation
    auto value = expr();
    consumeOptComment();
    if (auto* ve = dynamic_cast<VarExpr*>(target.get())) {
        auto s = std::make_unique<AssignStmt>();
        s->line = line;
        s->name = ve->name;
        switch (opt) {
        case TokenType::PLUS_EQUAL:
            s->op = '+';
            break;
        case TokenType::MINUS_EQUAL:
            s->op = '-';
            break;
        case TokenType::STAR_EQUAL:
            s->op = '*';
            break;
        case TokenType::SLASH_EQUAL:
            s->op = '/';
            break;
        case TokenType::PERCENT_EQUAL:
            s->op = '%';
            break;
        default:
            s->op = '\0';
            break;
        }
        s->value = std::move(value);
        return s;
    }
    if (auto* ie = dynamic_cast<IndexExpr*>(target.get())) {
        auto s = std::make_unique<IndexAssignStmt>();
        s->line = line;
        s->obj_expr = std::move(ie->obj); // conteneur (peut être lui-même chaîné)
        s->key = std::move(ie->key);
        s->op = opt;
        s->value = std::move(value);
        return s;
    }
    throw std::runtime_error("line " + std::to_string(line) + ": invalid assignment target");
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
    consumeOptComment();
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
    consumeOptComment();
    return s;
}

std::unique_ptr<Stmt> Parser::constantDecl() {
    int line = peek().line;
    advance(); // consume 'const'
    auto s = std::make_unique<VarDeclStmt>();
    s->is_constant = true;
    s->line = line;
    s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    while (match(TokenType::COMMA))
        s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    if (!check(TokenType::EQUALS))
        throw std::runtime_error("line " + std::to_string(line) + ": const '" + s->names[0] + "' must be initialized");
    advance(); // consume '='
    s->values.push_back(expr());
    while (match(TokenType::COMMA))
        s->values.push_back(expr());
    consumeOptComment();
    return s;
}

std::unique_ptr<Stmt> Parser::whileStmt() {
    int line = peek().line;
    advance();
    auto s = std::make_unique<WhileStmt>();
    s->line = line;
    s->cond = expr();
    skipComments();
    expect(TokenType::DO);
    while (true) {
        skipComments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;
        s->body.push_back(parseOneStmt());
    }
    expect(TokenType::END);
    consumeOptComment();
    return s;
}

std::unique_ptr<Stmt> Parser::ifStmt() {
    int line = peek().line;
    advance(); // IF
    auto s = std::make_unique<IfStmt>();
    s->line = line;
    s->cond = expr();
    skipComments();
    expect(TokenType::THEN);
    while (true) {
        skipComments();
        if (check(TokenType::ELSE) || check(TokenType::ELSEIF) || check(TokenType::END) || check(TokenType::EOF_T))
            break;
        s->then_body.push_back(parseOneStmt());
    }
    while (check(TokenType::ELSE) || check(TokenType::ELSEIF)) {
        bool is_elif = check(TokenType::ELSEIF);
        advance(); // ELSE or ELSEIF
        // Pas de sucre "else if" : pour un elseif on écrit 'elseif'. Un 'else' suivi
        // d'un 'if' est une branche else contenant un bloc if imbriqué (statement normal).
        if (is_elif) {
            ElseIfClause ei;
            ei.cond = expr();
            skipComments();
            expect(TokenType::THEN);
            while (true) {
                skipComments();
                if (check(TokenType::ELSE) || check(TokenType::ELSEIF) || check(TokenType::END) ||
                    check(TokenType::EOF_T))
                    break;
                ei.body.push_back(parseOneStmt());
            }
            s->else_ifs.push_back(std::move(ei));
        } else {
            consumeOptComment();
            while (true) {
                skipComments();
                if (check(TokenType::END) || check(TokenType::EOF_T))
                    break;
                s->else_body.push_back(parseOneStmt());
            }
            break;
        }
    }
    expect(TokenType::END);
    consumeOptComment();
    return s;
}

std::unique_ptr<Stmt> Parser::breakStmt() {
    int line = peek().line;
    advance();
    consumeOptComment();
    auto s = std::make_unique<BreakStmt>();
    s->line = line;
    return s;
}

std::unique_ptr<Stmt> Parser::continueStmt() {
    int line = peek().line;
    advance();
    consumeOptComment();
    auto s = std::make_unique<ContinueStmt>();
    s->line = line;
    return s;
}

std::unique_ptr<Stmt> Parser::throwStmt() {
    int line = peek().line;
    advance(); // throw
    auto s = std::make_unique<ThrowStmt>(expr());
    s->line = line;
    consumeOptComment();
    return s;
}

std::unique_ptr<Stmt> Parser::tryCatchStmt() {
    int line = peek().line;
    advance(); // try
    auto s = std::make_unique<TryCatchStmt>();
    s->line = line;
    consumeOptComment();
    while (true) {
        skipComments();
        if (check(TokenType::CATCH) || check(TokenType::EOF_T))
            break;
        s->try_body.push_back(parseOneStmt());
    }
    expect(TokenType::CATCH);
    s->catch_var = expect(TokenType::IDENTIFIER).lexeme;
    consumeOptComment();
    while (true) {
        skipComments();
        if (check(TokenType::ELSE) || check(TokenType::END) || check(TokenType::EOF_T))
            break;
        s->catch_body.push_back(parseOneStmt());
    }
    if (match(TokenType::ELSE)) {
        consumeOptComment();
        while (true) {
            skipComments();
            if (check(TokenType::END) || check(TokenType::EOF_T))
                break;
            s->else_body.push_back(parseOneStmt());
        }
    }
    expect(TokenType::END);
    consumeOptComment();
    return s;
}

std::unique_ptr<Stmt> Parser::funcDeclStmt() {
    int line = peek().line;
    advance(); // FUNC
    std::string name = expect(TokenType::IDENTIFIER).lexeme;

    // Parse "(" params ")" NL body "end" dans les champs fournis.
    auto parseParamsBody = [&](std::vector<std::string>& params, std::vector<std::unique_ptr<Expr>>& defaults,
                               bool& variadic, std::vector<std::unique_ptr<Stmt>>& body) {
        expect(TokenType::LPAREN);
        while (!check(TokenType::RPAREN) && !check(TokenType::EOF_T)) {
            if (check(TokenType::DOT_DOT_DOT)) {
                advance();
                variadic = true;
                break;
            }
            params.push_back(expect(TokenType::IDENTIFIER).lexeme);
            if (match(TokenType::EQUALS))
                defaults.push_back(expr());
            else
                defaults.push_back(nullptr);
            if (!check(TokenType::RPAREN))
                expect(TokenType::COMMA);
        }
        expect(TokenType::RPAREN);
        consumeOptComment();
        while (true) {
            skipComments();
            if (check(TokenType::END) || check(TokenType::EOF_T))
                break;
            body.push_back(parseOneStmt());
        }
        expect(TokenType::END);
        consumeOptComment();
    };

    // Définition sur un champ de map : func obj.field(params) ... end
    // → desugar en  obj.field = func(params) ... end
    if (check(TokenType::DOT)) {
        advance(); // DOT
        std::string field = expect(TokenType::IDENTIFIER).lexeme;
        auto fe = std::make_unique<FuncExpr>();
        parseParamsBody(fe->params, fe->defaults, fe->variadic, fe->body);
        auto ia = std::make_unique<IndexAssignStmt>();
        ia->line = line;
        ia->obj = name;
        ia->key = std::make_unique<StringExpr>(field);
        ia->op = TokenType::EQUALS;
        ia->value = std::move(fe);
        return ia;
    }

    auto s = std::make_unique<FuncDeclStmt>();
    s->line = line;
    s->name = name;
    parseParamsBody(s->params, s->defaults, s->variadic, s->body);
    return s;
}

std::unique_ptr<Stmt> Parser::returnStmt() {
    int line = peek().line;
    advance(); // RETURN
    auto s = std::make_unique<ReturnStmt>();
    s->line = line;
    // retvals optionnels : pas de valeur si on est sur une fermeture de bloc
    // (end/else/elseif/catch), un séparateur, un commentaire ou EOF.
    if (!check(TokenType::SEMICOLON) && !check(TokenType::COMMENT) && !check(TokenType::EOF_T)
        && !check(TokenType::END) && !check(TokenType::ELSE)
        && !check(TokenType::ELSEIF) && !check(TokenType::CATCH)) {
        if (check(TokenType::DOT_DOT_DOT)) {
            advance();
            s->spread_varargs = true;
        } else {
            s->values.push_back(expr());
            while (match(TokenType::COMMA)) {
                if (check(TokenType::DOT_DOT_DOT)) {
                    advance();
                    s->spread_varargs = true;
                    break;
                }
                s->values.push_back(expr());
            }
        }
    }
    consumeOptComment();
    return s;
}

std::unique_ptr<Stmt> Parser::multiAssignStmt() {
    int line = peek().line;
    auto s = std::make_unique<MultiAssignStmt>();
    s->line = line;

    // Parse LValue list
    auto parseLValue = [&]() {
        LValue lv;
        lv.name = expect(TokenType::IDENTIFIER).lexeme;
        if (match(TokenType::DOT)) {
            lv.field = expect(TokenType::IDENTIFIER).lexeme;
            if (check(TokenType::LBRACKET)) {
                advance();
                lv.kind = LValue::FIELD_INDEX;
                lv.key = expr();
                expect(TokenType::RBRACKET);
            } else {
                lv.kind = LValue::FIELD;
            }
        } else if (check(TokenType::LBRACKET)) {
            advance();
            lv.kind = LValue::INDEX;
            lv.key = expr();
            expect(TokenType::RBRACKET);
        } else {
            lv.kind = LValue::VAR;
        }
        return lv;
    };

    s->targets.push_back(parseLValue());
    while (match(TokenType::COMMA))
        s->targets.push_back(parseLValue());

    expect(TokenType::EQUALS);

    s->values.push_back(expr());
    while (match(TokenType::COMMA))
        s->values.push_back(expr());

    consumeOptComment();
    return s;
}

std::unique_ptr<Stmt> Parser::forStmt() {
    int line = peek().line;
    advance(); // FOR
    std::string first_var = expect(TokenType::IDENTIFIER).lexeme;

    if (match(TokenType::EQUALS)) {
        // for i=start,end[,step]  →  désucré en  for i in [start;end[;step]]
        auto range = std::make_unique<RangeExpr>();
        range->line = line;
        range->incl_left = true;
        range->incl_right = true;
        range->start = expr();
        expect(TokenType::COMMA);
        range->end = expr();
        if (match(TokenType::COMMA))
            range->step = expr();
        skipComments();
        expect(TokenType::DO);
        auto s = std::make_unique<ForIterStmt>();
        s->line = line;
        s->var1 = first_var;
        s->iter_expr = std::move(range);
        while (true) {
            skipComments();
            if (check(TokenType::END) || check(TokenType::EOF_T))
                break;
            s->body.push_back(parseOneStmt());
        }
        expect(TokenType::END);
        consumeOptComment();
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
    skipComments();
    expect(TokenType::DO);
    auto s = std::make_unique<ForIterStmt>();
    s->line = line;
    s->var1 = first_var;
    s->var2 = var2;
    s->iter_expr = std::move(iter_e);
    while (true) {
        skipComments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;
        s->body.push_back(parseOneStmt());
    }
    expect(TokenType::END);
    consumeOptComment();
    return s;
}

std::unique_ptr<Stmt> Parser::exprStmt() {
    int line = peek().line;
    auto e = expr();
    consumeOptComment();
    auto s = std::make_unique<ExprStmt>(std::move(e));
    s->line = line;
    return s;
}

// ── expressions ──────────────────────────────────────────────────────────────

std::unique_ptr<Expr> Parser::expr() {
    DepthGuard guard(depth_, peek().line);
    return logical();
}

std::unique_ptr<Expr> Parser::logical() {
    auto left = logicalAnd();
    while (true) {
        skipComments();
        if (!check(TokenType::OR))
            break;
        advance();
        skipComments();
        left = std::make_unique<BinaryExpr>('|', std::move(left), logicalAnd());
    }
    return left;
}

std::unique_ptr<Expr> Parser::logicalAnd() {
    auto left = bitwiseOr();
    while (true) {
        skipComments();
        if (!check(TokenType::AND))
            break;
        advance();
        skipComments();
        left = std::make_unique<BinaryExpr>('&', std::move(left), bitwiseOr());
    }
    return left;
}

std::unique_ptr<Expr> Parser::bitwiseOr() {
    auto left = bitwiseXor();
    while (true) {
        skipComments();
        if (!check(TokenType::PIPE))
            break;
        advance();
        skipComments();
        left = std::make_unique<BinaryExpr>('o', std::move(left), bitwiseXor());
    }
    return left;
}

std::unique_ptr<Expr> Parser::bitwiseXor() {
    auto left = bitwiseAnd();
    while (true) {
        skipComments();
        if (!check(TokenType::TILDE))
            break; // '~' binaire = XOR (modèle Lua)
        advance();
        skipComments();
        left = std::make_unique<BinaryExpr>('x', std::move(left), bitwiseAnd());
    }
    return left;
}

std::unique_ptr<Expr> Parser::bitwiseAnd() {
    auto left = comparison();
    while (true) {
        skipComments();
        if (!check(TokenType::AMP))
            break;
        advance();
        skipComments();
        left = std::make_unique<BinaryExpr>('b', std::move(left), comparison());
    }
    return left;
}

static bool isCmpToken(TokenType t) {
    return t == TokenType::GREATER || t == TokenType::LESS || t == TokenType::GREATER_EQUAL ||
           t == TokenType::LESS_EQUAL || t == TokenType::EQUAL_EQUAL || t == TokenType::NOT_EQUAL;
}
static char cmpChar(TokenType t) {
    if (t == TokenType::EQUAL_EQUAL)
        return '=';
    if (t == TokenType::GREATER_EQUAL)
        return 'G';
    if (t == TokenType::LESS_EQUAL)
        return 'L';
    if (t == TokenType::NOT_EQUAL)
        return 'N';
    if (t == TokenType::GREATER)
        return '>';
    return '<';
}

std::unique_ptr<Expr> Parser::comparison() {
    auto first = shift();
    skipComments();
    if (!isCmpToken(peek().type))
        return first;

    // collect all operands and operators
    auto chain = std::make_unique<ChainedCompareExpr>();
    chain->operands.push_back(std::move(first));
    while (isCmpToken(peek().type)) {
        chain->ops.push_back(cmpChar(advance().type));
        skipComments();
        chain->operands.push_back(shift());
        skipComments();
    }
    // single comparison: return a plain BinaryExpr for simplicity
    if (chain->ops.size() == 1)
        return std::make_unique<BinaryExpr>(chain->ops[0], std::move(chain->operands[0]),
                                            std::move(chain->operands[1]));
    return chain;
}

std::unique_ptr<Expr> Parser::shift() {
    auto left = additive();
    while (true) {
        skipComments();
        if (!check(TokenType::LSHIFT) && !check(TokenType::RSHIFT))
            break;
        char op = check(TokenType::LSHIFT) ? 'l' : 'r';
        advance();
        skipComments();
        left = std::make_unique<BinaryExpr>(op, std::move(left), additive());
    }
    return left;
}

std::unique_ptr<Expr> Parser::additive() {
    auto left = multiplicative();
    while (true) {
        skipComments();
        if (!check(TokenType::PLUS) && !check(TokenType::MINUS))
            break;
        char op = advance().lexeme[0];
        skipComments();
        left = std::make_unique<BinaryExpr>(op, std::move(left), multiplicative());
    }
    return left;
}

std::unique_ptr<Expr> Parser::multiplicative() {
    auto left = unary();
    while (true) {
        skipComments();
        if (!check(TokenType::STAR) && !check(TokenType::SLASH) && !check(TokenType::SLASH_SLASH) &&
            !check(TokenType::PERCENT))
            break;
        char op = check(TokenType::SLASH_SLASH) ? (advance(), 'q') : advance().lexeme[0];
        skipComments();
        left = std::make_unique<BinaryExpr>(op, std::move(left), unary());
    }
    return left;
}

// Précédence (modèle Lua) : '^' (puissance) lie plus fort que le moins unaire.
//   multiplicative → unary → power → primary
//   -2 ^ 2 == -(2^2) == -4 ;  2 ^ -1 == 0.5 ;  2 ^ 2 ^ 3 == 2^(2^3) (droite)
std::unique_ptr<Expr> Parser::unary() {
    if (check(TokenType::MINUS)) {
        advance();
        return std::make_unique<UnaryExpr>('-', unary());
    }
    if (check(TokenType::NOT)) {
        advance();
        return std::make_unique<UnaryExpr>('!', unary());
    }
    if (check(TokenType::TILDE)) {
        advance();
        return std::make_unique<UnaryExpr>('~', unary());
    }
    if (check(TokenType::HASH)) {
        advance();
        auto e = std::make_unique<CallExpr>();
        e->callee = "len";
        e->args.push_back(unary());
        return e;
    }
    return power();
}

std::unique_ptr<Expr> Parser::power() {
    auto left = primary();
    skipComments();
    if (!check(TokenType::CARET))
        return left; // '^' = puissance (modèle Lua)
    advance();
    skipComments();
    // opérande droit = unary → autorise 2 ^ -1 et associativité à droite (2^2^3)
    return std::make_unique<BinaryExpr>('p', std::move(left), unary());
}

std::unique_ptr<Expr> Parser::parsePostfix(std::unique_ptr<Expr> base) {
    while (check(TokenType::LBRACKET) || check(TokenType::DOT) || check(TokenType::LPAREN) ||
           (check(TokenType::QUESTION) && peekNextType() == TokenType::LPAREN)) {
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
            bool opt_m = check(TokenType::QUESTION) && peekNextType() == TokenType::LPAREN;
            if (check(TokenType::LPAREN) || opt_m) {
                if (opt_m)
                    advance(); // consume '?'
                advance();     // consume LPAREN
                auto mc = std::make_unique<MethodCallExpr>();
                mc->receiver = std::move(base);
                mc->method = field;
                mc->is_super = false;
                mc->optional = opt_m;
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
        } else { // LPAREN ou QUESTION+LPAREN (appel optionnel)
            bool opt = false;
            if (check(TokenType::QUESTION)) {
                advance();
                opt = true;
            }
            advance(); // consume LPAREN
            auto call = std::make_unique<ExprCallExpr>();
            call->callee = std::move(base);
            call->optional = opt;
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
            if (depth == 0)
                return false; // closing bracket at depth 0 = end of array
            depth--;
        } else if (depth == 0) {
            if (t == TokenType::SEMICOLON)
                return true;
            if (t == TokenType::COMMA)
                return false;
            if (t == TokenType::EOF_T)
                return false;
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
        throw std::runtime_error("line " + std::to_string(peek().line) + ": expected ']' or '[' to close range");
    }

    // Ajustement open-left (incl_left=false → start += step) : émis par le
    // COMPILATEUR à partir du drapeau node->incl_left. Rien à faire ici.
    return node;
}

std::unique_ptr<Expr> Parser::primary() {
    if (check(TokenType::NUMBER)) {
        Token tok = advance();
        const std::string& lex = tok.lexeme;
        try {
            // 0x.. / 0o.. / 0b.. : entiers base 16/8/2 (stoull → bit-pattern complet, wrapping int64)
            if (lex.size() > 2 && lex[0] == '0' && (lex[1] == 'x' || lex[1] == 'X'))
                return std::make_unique<NumberExpr>(static_cast<int64_t>(std::stoull(lex.substr(2), nullptr, 16)));
            if (lex.size() > 2 && lex[0] == '0' && (lex[1] == 'o' || lex[1] == 'O'))
                return std::make_unique<NumberExpr>(static_cast<int64_t>(std::stoull(lex.substr(2), nullptr, 8)));
            if (lex.size() > 2 && lex[0] == '0' && (lex[1] == 'b' || lex[1] == 'B'))
                return std::make_unique<NumberExpr>(static_cast<int64_t>(std::stoull(lex.substr(2), nullptr, 2)));
            // flottant si '.' OU exposant scientifique ('e'/'E') ; sinon entier.
            // (les préfixes hex/oct/bin sont déjà traités au-dessus.)
            if (lex.find('.') == std::string::npos && lex.find('e') == std::string::npos &&
                lex.find('E') == std::string::npos)
                return std::make_unique<NumberExpr>(static_cast<int64_t>(std::stoll(lex)));
            return std::make_unique<NumberExpr>(std::stod(lex));
        } catch (const std::out_of_range&) {
            throw std::runtime_error("line " + std::to_string(tok.line) + ": numeric literal out of range: " + lex);
        }
    }
    if (check(TokenType::STRING))
        return parsePostfix(std::make_unique<StringExpr>(advance().lexeme));
    if (check(TokenType::TRUE)) {
        advance();
        return std::make_unique<BoolExpr>(true);
    }
    if (check(TokenType::FALSE)) {
        advance();
        return std::make_unique<BoolExpr>(false);
    }
    if (check(TokenType::IDENTIFIER)) {
        std::string name = advance().lexeme;
        // super.method(args) — appel de la méthode parente avec le self courant
        if (name == "super") {
            expect(TokenType::DOT);
            std::string method_name = expect(TokenType::IDENTIFIER).lexeme;
            bool opt_super = check(TokenType::QUESTION) && peekNextType() == TokenType::LPAREN;
            if (opt_super)
                advance(); // consume '?'
            if (!check(TokenType::LPAREN))
                throw std::runtime_error("line " + std::to_string(peek().line) +
                                         ": super: seuls les appels de méthode sont supportés");
            advance(); // LPAREN
            auto mc = std::make_unique<MethodCallExpr>();
            mc->receiver = nullptr;
            mc->method = method_name;
            mc->is_super = true;
            mc->optional = opt_super;
            if (!check(TokenType::RPAREN)) {
                mc->args.push_back(expr());
                while (match(TokenType::COMMA))
                    mc->args.push_back(expr());
            }
            expect(TokenType::RPAREN);
            return parsePostfix(std::move(mc));
        }
        // appel optionnel : F?()  → n'appelle que si F est callable, sinon nil
        bool opt_call = check(TokenType::QUESTION) && peekNextType() == TokenType::LPAREN;
        if (opt_call)
            advance(); // consume '?'
        if (match(TokenType::LPAREN)) {
            auto call = std::make_unique<CallExpr>();
            call->callee = name;
            call->optional = opt_call;
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
    if (check(TokenType::NIL)) {
        advance();
        return std::make_unique<NilExpr>();
    }
    if (check(TokenType::DOT_DOT_DOT)) {
        advance();
        return std::make_unique<VarArgExpr>();
    }
    if (check(TokenType::FUNC)) {
        advance(); // FUNC
        auto fe = std::make_unique<FuncExpr>();
        expect(TokenType::LPAREN);
        while (!check(TokenType::RPAREN) && !check(TokenType::EOF_T)) {
            if (check(TokenType::DOT_DOT_DOT)) {
                advance();
                fe->variadic = true;
                break;
            }
            fe->params.push_back(expect(TokenType::IDENTIFIER).lexeme);
            if (match(TokenType::EQUALS))
                fe->defaults.push_back(expr());
            else
                fe->defaults.push_back(nullptr);
            if (!check(TokenType::RPAREN))
                expect(TokenType::COMMA);
        }
        expect(TokenType::RPAREN);
        consumeOptComment();
        while (true) {
            skipComments();
            if (check(TokenType::END) || check(TokenType::EOF_T))
                break;
            fe->body.push_back(parseOneStmt());
        }
        expect(TokenType::END);
        return parsePostfix(std::move(fe));
    }
    if (check(TokenType::LBRACE)) {
        advance(); // consume {
        skipComments();
        auto map = std::make_unique<MapExpr>();
        while (!check(TokenType::RBRACE) && !check(TokenType::EOF_T)) {
            std::unique_ptr<Expr> key;
            switch (peek().type) {
            case TokenType::STRING:
            case TokenType::IDENTIFIER:
                key = std::make_unique<StringExpr>(advance().lexeme);
                break;
            case TokenType::LBRACKET:
                advance();
                key = expr();
                expect(TokenType::RBRACKET);
                break;
            default:
                throw std::runtime_error("line " + std::to_string(peek().line) +
                                         ": expected string, identifier, or [expr] key in map literal");
            }
            expect(TokenType::COLON);
            auto val = expr();
            map->entries.push_back({std::move(key), std::move(val)});
            if (check(TokenType::COMMA))
                advance();
            skipComments();
        }
        expect(TokenType::RBRACE);
        return parsePostfix(std::move(map));
    }
    if (check(TokenType::LBRACKET)) {
        advance(); // consume [
        // Check if this is a range [a;b] or array [a,b,c]
        if (looksLikeRange()) {
            return rangeExpr(true); // incl_left=true
        }
        skipComments();
        auto arr = std::make_unique<ArrayExpr>();
        while (!check(TokenType::RBRACKET) && !check(TokenType::EOF_T)) {
            arr->elements.push_back(expr());
            if (check(TokenType::COMMA))
                advance();
            skipComments();
        }
        expect(TokenType::RBRACKET);
        return parsePostfix(std::move(arr));
    }
    if (check(TokenType::RBRACKET)) {
        // Open-left range: ]a;b]  or  ]a;b[
        advance();               // consume ]
        return rangeExpr(false); // incl_left=false
    }
    if (match(TokenType::LPAREN)) {
        skipComments();
        auto e = expr();
        skipComments();
        expect(TokenType::RPAREN);
        // postfix sur une expression parenthésée : (expr)(args), (expr)[i], (expr).champ
        return parsePostfix(std::move(e));
    }
    throw std::runtime_error("line " + std::to_string(peek().line) + ": unexpected token '" + peek().lexeme + "'");
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
    consumeOptComment();
    while (true) {
        skipComments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;
        bool is_static = false;
        if (check(TokenType::STATIC)) {
            advance(); // consomme 'static'
            is_static = true;
        }
        if (!check(TokenType::FUNC))
            throw std::runtime_error("line " + std::to_string(peek().line) + ": expected 'func' inside class body");
        int method_line = peek().line;
        // funcDeclStmt() renvoie un IndexAssignStmt pour la forme `func obj.field()`
        // — invalide dans une classe. Vérifier le type au lieu d'un static_cast
        // aveugle (qui provoquait un segfault).
        auto raw = funcDeclStmt();
        auto* fd = dynamic_cast<FuncDeclStmt*>(raw.get());
        if (!fd)
            throw std::runtime_error("line " + std::to_string(method_line) +
                                     ": une méthode de classe doit être 'func nom(...)' (pas 'func obj.champ(...)')");
        raw.release();
        auto method = std::unique_ptr<FuncDeclStmt>(fd);
        method->is_static = is_static;
        s->methods.push_back(std::move(method));
    }
    expect(TokenType::END);
    consumeOptComment();
    return s;
}

static std::vector<std::string> collectTopLevelNames(const std::vector<std::unique_ptr<Stmt>>& stmts) {
    std::vector<std::string> names;
    for (auto& s : stmts) {
        if (auto* v = dynamic_cast<const VarDeclStmt*>(s.get()))
            for (auto& n : v->names)
                names.push_back(n);
        else if (auto* f = dynamic_cast<const FuncDeclStmt*>(s.get()))
            names.push_back(f->name);
        else if (auto* c = dynamic_cast<const ClassDeclStmt*>(s.get()))
            names.push_back(c->name); // les classes sont aussi des noms exportés
    }
    return names;
}

std::unique_ptr<Stmt> Parser::importStmt() {
    advance(); // consomme 'import'
    Token path_tok = expect(TokenType::STRING);
    std::string path = path_tok.lexeme;
    if (path.size() < 3 || path.substr(path.size() - 3) != ".ol")
        path += ".ol";

    std::string alias;
    if (check(TokenType::AS)) {
        advance();
        alias = expect(TokenType::IDENTIFIER).lexeme;
    }
    consumeOptComment();

    // Résoudre le chemin par rapport au répertoire du script courant
    std::string resolved =
        (!path.empty() && (path[0] == '/' || (path.size() > 1 && path[1] == ':'))) ? path : base_dir_ + path;

    auto block = std::make_unique<BlockStmt>();

    // Construit `var al = {}` puis `al[n] = n` pour chaque nom exporté (référence
    // les globales déjà injectées). Partagé par le cas « déjà importé » et le
    // cas frais.
    auto emitAliasMap = [&](const std::string& al, const std::vector<std::string>& names) {
        auto vd = std::make_unique<VarDeclStmt>();
        vd->names.push_back(al);
        vd->values.push_back(std::make_unique<MapExpr>());
        block->stmts.push_back(std::move(vd));
        for (auto& tname : names) {
            auto ia = std::make_unique<IndexAssignStmt>();
            ia->obj = al;
            ia->key = std::make_unique<StringExpr>(tname);
            ia->op = TokenType::EQUALS;
            ia->value = std::make_unique<VarExpr>(tname);
            block->stmts.push_back(std::move(ia));
        }
    };

    // Déjà importé (dédup / rupture de cycle) : ne PAS ré-injecter les instructions.
    // Si un alias est demandé, reconstruire sa map depuis les noms mis en cache au
    // 1er import — sinon un 2e `import "m" as b` donnerait une map vide.
    if (imported_paths_->count(resolved)) {
        if (!alias.empty()) {
            auto it = module_names_->find(resolved);
            emitAliasMap(alias, it != module_names_->end() ? it->second : std::vector<std::string>{});
        }
        return block;
    }
    imported_paths_->insert(resolved);

    // Lire le fichier importé : d'abord depuis le registre en mémoire (fourni
    // par l'hôte, ex. le playground WASM), sinon depuis le disque.
    std::string src_text;
    if (!source_get(resolved, src_text) && !(resolved != path && source_get(path, src_text))) {
        std::ifstream f(resolved);
        if (!f)
            throw std::runtime_error("import: cannot open '" + resolved + "'");
        std::ostringstream ss;
        ss << f.rdbuf();
        src_text = ss.str();
    }

    auto sep2 = resolved.find_last_of("/\\");
    std::string sub_dir = (sep2 != std::string::npos) ? resolved.substr(0, sep2 + 1) : base_dir_;

    Parser sub_parser(Lexer(src_text).tokenize(), sub_dir, imported_paths_, module_names_);
    Program sub_prog = sub_parser.parse();

    // Mémorise les noms exportés (même pour un import flat) → un import aliasé
    // ultérieur du même module pourra reconstruire sa map.
    auto top_names = collectTopLevelNames(sub_prog.stmts);
    (*module_names_)[resolved] = top_names;

    if (alias.empty()) {
        // import flat : injecter directement toutes les instructions
        for (auto& s : sub_prog.stmts)
            block->stmts.push_back(std::move(s));
    } else {
        // import as name : var name = {}; <stmts>; name[k] = k pour chaque nom top-level
        auto vd = std::make_unique<VarDeclStmt>();
        vd->names.push_back(alias);
        vd->values.push_back(std::make_unique<MapExpr>());
        block->stmts.push_back(std::move(vd));

        for (auto& s : sub_prog.stmts)
            block->stmts.push_back(std::move(s));

        for (auto& tname : top_names) {
            auto ia = std::make_unique<IndexAssignStmt>();
            ia->obj = alias;
            ia->key = std::make_unique<StringExpr>(tname);
            ia->op = TokenType::EQUALS;
            ia->value = std::make_unique<VarExpr>(tname);
            block->stmts.push_back(std::move(ia));
        }
    }
    return block;
}

std::unique_ptr<Stmt> Parser::switchStmt() {
    int line = peek().line;
    advance(); // SWITCH
    auto s = std::make_unique<SwitchStmt>();
    s->line = line;
    s->subject = expr();
    consumeOptComment();

    auto isArmStart = [&]() {
        return check(TokenType::CASE) || check(TokenType::ELSE) || check(TokenType::END) || check(TokenType::EOF_T);
    };

    while (true) {
        skipComments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;

        if (check(TokenType::ELSE)) {
            advance(); // ELSE
            consumeOptComment();
            while (!check(TokenType::END) && !check(TokenType::EOF_T)) {
                skipComments();
                if (check(TokenType::END) || check(TokenType::EOF_T))
                    break;
                s->else_body.push_back(parseOneStmt());
            }
            break;
        }

        expect(TokenType::CASE);
        CaseClause arm;
        arm.values.push_back(expr());
        while (check(TokenType::COMMA)) {
            advance(); // COMMA
            arm.values.push_back(expr());
        }
        consumeOptComment();
        while (!isArmStart()) {
            skipComments();
            if (isArmStart())
                break;
            arm.body.push_back(parseOneStmt());
        }
        s->cases.push_back(std::move(arm));
    }

    expect(TokenType::END);
    consumeOptComment();
    return s;
}
