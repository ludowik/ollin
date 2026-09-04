#include "parser.h"
#include "paths.h"
#include "lexer.h"
#include "source_registry.h"
#include <fstream>
#include <sstream>
#include <stdexcept>

Parser::Parser(std::vector<Token> tokens, std::string base_dir,
               std::shared_ptr<std::unordered_set<std::string>> imported,
               std::shared_ptr<std::unordered_map<std::string, std::vector<std::string>>> module_names,
               std::shared_ptr<std::vector<std::string>> source_files, std::string /*filename*/)
    : tokens(std::move(tokens)), base_dir_(std::move(base_dir)),
      imported_paths_(imported ? std::move(imported) : std::make_shared<std::unordered_set<std::string>>()),
      module_names_(module_names ? std::move(module_names)
                                 : std::make_shared<std::unordered_map<std::string, std::vector<std::string>>>()),
      source_files_(source_files ? std::move(source_files) : std::make_shared<std::vector<std::string>>()) {
    // current_file_idx_ is updated from token.file_idx in advance()
    if (!this->tokens.empty())
        current_file_idx_ = this->tokens[0].file_idx;
}

const Token& Parser::peek() const {
    return tokens[pos];
}
const Token& Parser::advance() {
    const Token& t = tokens[pos++];
    current_file_idx_ = t.file_idx;
    return t;
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
        throw std::runtime_error(cur_loc(tokens[pos].line).str(*source_files_) + ": unexpected token '" +
                                 tokens[pos].lexeme + "'");
    return advance();
}

TokenType Parser::peek_next_type() const {
    if (pos + 1 < static_cast<int>(tokens.size()))
        return tokens[pos + 1].type;
    return TokenType::EOF_T;
}

void Parser::skip_comments() {
    while (check(TokenType::COMMENT))
        advance();
}

// Absorbs an optional COMMENT at the end of a statement. Statements are separated by
// newlines, which are not tokenized; there is no automatic semicolon insertion.
void Parser::consume_opt_comment() {
    match(TokenType::COMMENT);
}

// Stack-overflow guard: recursive descent (parentheses, calls, nested blocks) could crash the
// process on deeply nested input. Depth is bounded and a clean error is raised instead.
namespace {
struct DepthGuard {
    int& d;
    std::string prefix;
    DepthGuard(int& depth, std::string loc) : d(depth), prefix(std::move(loc)) {
        if (++d > 256)
            throw std::runtime_error(prefix + ": nesting too deep");
    }
    ~DepthGuard() {
        --d;
    }
};
} // namespace


Program Parser::parse() {
    Program prog;
    while (true) {
        skip_comments();
        if (check(TokenType::EOF_T))
            break;
        prog.stmts.push_back(parse_one_stmt());
    }
    prog.source_files = *source_files_;
    return prog;
}


static bool is_assign_op(TokenType t) {
    return t == TokenType::EQUALS || t == TokenType::PLUS_EQUAL || t == TokenType::MINUS_EQUAL ||
           t == TokenType::STAR_EQUAL || t == TokenType::SLASH_EQUAL || t == TokenType::PERCENT_EQUAL;
}

std::unique_ptr<Stmt> Parser::parse_one_stmt() {
    DepthGuard guard(depth_, peek().sloc().str(*source_files_));
    switch (peek().type) {
    case TokenType::COMMENT: {
        std::string text = advance().lexeme;
        consume_opt_comment();
        return std::make_unique<CommentStmt>(std::move(text));
    }
    case TokenType::SEMICOLON:
        // ';' is only valid inside a range [a;b], where range_expr consumes it. At statement
        // level it is an error, reported explicitly.
        throw std::runtime_error(peek().sloc().str(*source_files_) +
                                 ": ';' is not valid syntax — statements are terminated by newlines");
    case TokenType::WHILE:    return while_stmt();
    case TokenType::DO:       return do_stmt();
    case TokenType::IF:       return if_stmt();
    case TokenType::BREAK:    return break_stmt();
    case TokenType::CONTINUE: return continue_stmt();
    case TokenType::TRY:      return try_catch_stmt();
    case TokenType::THROW:    return throw_stmt();
    case TokenType::FOR:      return for_stmt();
    case TokenType::IMPORT:   return import_stmt();
    case TokenType::CLASS:    return class_decl();
    case TokenType::ENUM:     return enum_decl();
    case TokenType::SWITCH:   return switch_stmt();
    case TokenType::FUNC:     return func_decl_stmt();
    case TokenType::RETURN:   return return_stmt();
    case TokenType::VAR:      return var_decl();
    case TokenType::GLOBAL:   return global_decl();
    case TokenType::CONSTANT: return constant_decl();
    case TokenType::IDENTIFIER: {
        // A statement starting with an identifier is an assignment (plain, indexed or
        // chained), a multi-assignment, or an expression statement. We parse an expression and
        // decide from what follows: an assignment operator, a comma, or nothing. An assignment
        // target must be an lvalue (VarExpr or IndexExpr), which uniformly covers a=, a.b=,
        // a[i]=, a.b.c=, a[i][j]= and a.b[k]= (see the grammar).
        int line = peek().line;
        int saved = pos;
        auto e = expr();
        if (is_assign_op(peek().type))
            return finish_assign_from_expr(std::move(e), line);
        if (check(TokenType::COMMA)) {
            pos = saved; // a multiple assignment: re-parsed by multi_assign_stmt (LValue)
            return multi_assign_stmt();
        }
        consume_opt_comment();
        auto st = std::make_unique<ExprStmt>(std::move(e));
        st->line = line; st->file_idx = current_file_idx_;
        return st;
    }
    default:
        break;
    }
    return expr_stmt();
}

// Turns an already parsed target plus the current assignment operator into a statement:
// VarExpr becomes an AssignStmt, IndexExpr (a.b, a[i] and chains) an IndexAssignStmt carrying
// the container in obj_expr.
std::unique_ptr<Stmt> Parser::finish_assign_from_expr(std::unique_ptr<Expr> target, int line) {
    TokenType opt = advance().type;   // assignment operator
    auto value = expr();
    consume_opt_comment();
    if (auto* ve = dynamic_cast<VarExpr*>(target.get())) {
        auto s = std::make_unique<AssignStmt>();
        s->line = line; s->file_idx = current_file_idx_;
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
        s->line = line; s->file_idx = current_file_idx_;
        s->obj_expr = std::move(ie->obj); // the container, which may itself be chained
        s->key = std::move(ie->key);
        s->op = opt;
        s->value = std::move(value);
        return s;
    }
    throw std::runtime_error(cur_loc(line).str(*source_files_) + ": invalid assignment target");
}


std::unique_ptr<Stmt> Parser::var_decl() {
    int line = peek().line;
    advance();
    auto s = std::make_unique<VarDeclStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    while (match(TokenType::COMMA))
        s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    if (match(TokenType::EQUALS)) {
        s->values.push_back(expr());
        while (match(TokenType::COMMA))
            s->values.push_back(expr());
    }
    // Without '=' the values are absent and become nil in the compiler.
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::global_decl() {
    int line = peek().line;
    advance(); // consume 'global'
    auto s = std::make_unique<VarDeclStmt>();
    s->is_global = true;
    s->line = line; s->file_idx = current_file_idx_;
    s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    while (match(TokenType::COMMA))
        s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    if (match(TokenType::EQUALS)) {
        s->values.push_back(expr());
        while (match(TokenType::COMMA))
            s->values.push_back(expr());
    }
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::constant_decl() {
    int line = peek().line;
    advance(); // consume 'const'
    auto s = std::make_unique<VarDeclStmt>();
    s->is_constant = true;
    s->line = line; s->file_idx = current_file_idx_;
    s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    while (match(TokenType::COMMA))
        s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    if (!check(TokenType::EQUALS))
        throw std::runtime_error(cur_loc(line).str(*source_files_) + ": const '" + s->names[0] + "' must be initialized");
    advance(); // consume '='
    s->values.push_back(expr());
    while (match(TokenType::COMMA))
        s->values.push_back(expr());
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::while_stmt() {
    int line = peek().line;
    advance();
    auto s = std::make_unique<WhileStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    s->cond = expr();
    skip_comments();
    expect(TokenType::DO);
    while (true) {
        skip_comments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;
        s->body.push_back(parse_one_stmt());
    }
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::do_stmt() {
    int line = peek().line;
    advance();
    auto s = std::make_unique<DoStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    while (true) {
        skip_comments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;
        s->body.push_back(parse_one_stmt());
    }
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::if_stmt() {
    int line = peek().line;
    advance(); // IF
    auto s = std::make_unique<IfStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    s->cond = expr();
    skip_comments();
    expect(TokenType::THEN);
    while (true) {
        skip_comments();
        if (check(TokenType::ELSE) || check(TokenType::ELSEIF) || check(TokenType::END) || check(TokenType::EOF_T))
            break;
        s->then_body.push_back(parse_one_stmt());
    }
    while (check(TokenType::ELSE) || check(TokenType::ELSEIF)) {
        bool is_elif = check(TokenType::ELSEIF);
        advance(); // ELSE or ELSEIF
        // There is no "else if" sugar: an elseif is spelled 'elseif'. An 'else' followed by an
        // 'if' is an else branch containing a nested if block, like any other statement.
        if (is_elif) {
            ElseIfClause ei;
            ei.cond = expr();
            skip_comments();
            expect(TokenType::THEN);
            while (true) {
                skip_comments();
                if (check(TokenType::ELSE) || check(TokenType::ELSEIF) || check(TokenType::END) ||
                    check(TokenType::EOF_T))
                    break;
                ei.body.push_back(parse_one_stmt());
            }
            s->else_ifs.push_back(std::move(ei));
        } else {
            consume_opt_comment();
            while (true) {
                skip_comments();
                if (check(TokenType::END) || check(TokenType::EOF_T))
                    break;
                s->else_body.push_back(parse_one_stmt());
            }
            break;
        }
    }
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::break_stmt() {
    int line = peek().line;
    advance();
    consume_opt_comment();
    auto s = std::make_unique<BreakStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    return s;
}

std::unique_ptr<Stmt> Parser::continue_stmt() {
    int line = peek().line;
    advance();
    consume_opt_comment();
    auto s = std::make_unique<ContinueStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    return s;
}

std::unique_ptr<Stmt> Parser::throw_stmt() {
    int line = peek().line;
    advance(); // throw
    auto s = std::make_unique<ThrowStmt>(expr());
    s->line = line; s->file_idx = current_file_idx_;
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::try_catch_stmt() {
    int line = peek().line;
    advance(); // try
    auto s = std::make_unique<TryCatchStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    consume_opt_comment();
    while (true) {
        skip_comments();
        if (check(TokenType::CATCH) || check(TokenType::EOF_T))
            break;
        s->try_body.push_back(parse_one_stmt());
    }
    expect(TokenType::CATCH);
    s->catch_var = expect(TokenType::IDENTIFIER).lexeme;
    consume_opt_comment();
    while (true) {
        skip_comments();
        if (check(TokenType::ELSE) || check(TokenType::END) || check(TokenType::EOF_T))
            break;
        s->catch_body.push_back(parse_one_stmt());
    }
    if (match(TokenType::ELSE)) {
        consume_opt_comment();
        while (true) {
            skip_comments();
            if (check(TokenType::END) || check(TokenType::EOF_T))
                break;
            s->else_body.push_back(parse_one_stmt());
        }
    }
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::func_decl_stmt() {
    int line = peek().line;
    advance(); // FUNC
    std::string name = expect(TokenType::IDENTIFIER).lexeme;

    // Parses "(" params ")" NL body "end" into the fields provided.
    auto parse_params_body = [&](std::vector<std::string>& params, std::vector<std::unique_ptr<Expr>>& defaults,
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
        consume_opt_comment();
        while (true) {
            skip_comments();
            if (check(TokenType::END) || check(TokenType::EOF_T))
                break;
            body.push_back(parse_one_stmt());
        }
        expect(TokenType::END);
        consume_opt_comment();
    };

    // Definition on a map field: func obj.field(params) ... end
    // → desugared into  obj.field = func(params) ... end
    if (check(TokenType::DOT)) {
        advance(); // DOT
        std::string field = expect(TokenType::IDENTIFIER).lexeme;
        auto fe = std::make_unique<FuncExpr>();
        parse_params_body(fe->params, fe->defaults, fe->variadic, fe->body);
        auto ia = std::make_unique<IndexAssignStmt>();
        ia->line = line; ia->file_idx = current_file_idx_;
        ia->obj = name;
        ia->key = std::make_unique<StringExpr>(field);
        ia->op = TokenType::EQUALS;
        ia->value = std::move(fe);
        return ia;
    }

    auto s = std::make_unique<FuncDeclStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    s->name = name;
    parse_params_body(s->params, s->defaults, s->variadic, s->body);
    return s;
}

std::unique_ptr<Stmt> Parser::return_stmt() {
    int line = peek().line;
    advance(); // RETURN
    auto s = std::make_unique<ReturnStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    // Return values are optional: none when we are on a block terminator.
    // (end/else/elseif/catch), a separator, a comment, or EOF.
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
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::multi_assign_stmt() {
    int line = peek().line;
    auto s = std::make_unique<MultiAssignStmt>();
    s->line = line; s->file_idx = current_file_idx_;

    // Parse LValue list
    auto parse_l_value = [&]() {
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

    s->targets.push_back(parse_l_value());
    while (match(TokenType::COMMA))
        s->targets.push_back(parse_l_value());

    expect(TokenType::EQUALS);

    s->values.push_back(expr());
    while (match(TokenType::COMMA))
        s->values.push_back(expr());

    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::for_stmt() {
    int line = peek().line;
    advance(); // FOR
    std::string first_var = expect(TokenType::IDENTIFIER).lexeme;

    if (match(TokenType::EQUALS)) {
        // for i=start,end[,step] is desugared into for i in [start;end[;step]]
        auto range = std::make_unique<RangeExpr>();
        range->line = line;
        range->incl_left = true;
        range->incl_right = true;
        range->start = expr();
        expect(TokenType::COMMA);
        range->end = expr();
        if (match(TokenType::COMMA))
            range->step = expr();
        skip_comments();
        expect(TokenType::DO);
        auto s = std::make_unique<ForIterStmt>();
        s->line = line; s->file_idx = current_file_idx_;
        s->var1 = first_var;
        s->iter_expr = std::move(range);
        while (true) {
            skip_comments();
            if (check(TokenType::END) || check(TokenType::EOF_T))
                break;
            s->body.push_back(parse_one_stmt());
        }
        expect(TokenType::END);
        consume_opt_comment();
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
    skip_comments();
    expect(TokenType::DO);
    auto s = std::make_unique<ForIterStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    s->var1 = first_var;
    s->var2 = var2;
    s->iter_expr = std::move(iter_e);
    while (true) {
        skip_comments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;
        s->body.push_back(parse_one_stmt());
    }
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::expr_stmt() {
    int line = peek().line;
    auto e = expr();
    consume_opt_comment();
    auto s = std::make_unique<ExprStmt>(std::move(e));
    s->line = line; s->file_idx = current_file_idx_;
    return s;
}


std::unique_ptr<Expr> Parser::expr() {
    DepthGuard guard(depth_, peek().sloc().str(*source_files_));
    return logical();
}

std::unique_ptr<Expr> Parser::logical() {
    auto left = logical_and();
    while (true) {
        skip_comments();
        if (!check(TokenType::OR))
            break;
        advance();
        skip_comments();
        left = std::make_unique<BinaryExpr>('|', std::move(left), logical_and());
    }
    return left;
}

std::unique_ptr<Expr> Parser::logical_and() {
    auto left = bitwise_or();
    while (true) {
        skip_comments();
        if (!check(TokenType::AND))
            break;
        advance();
        skip_comments();
        left = std::make_unique<BinaryExpr>('&', std::move(left), bitwise_or());
    }
    return left;
}

std::unique_ptr<Expr> Parser::bitwise_or() {
    auto left = bitwise_xor();
    while (true) {
        skip_comments();
        if (!check(TokenType::PIPE))
            break;
        advance();
        skip_comments();
        left = std::make_unique<BinaryExpr>('o', std::move(left), bitwise_xor());
    }
    return left;
}

std::unique_ptr<Expr> Parser::bitwise_xor() {
    auto left = bitwise_and();
    while (true) {
        skip_comments();
        if (!check(TokenType::TILDE))
            break; // a binary '~' is XOR, as in Lua
        advance();
        skip_comments();
        left = std::make_unique<BinaryExpr>('x', std::move(left), bitwise_and());
    }
    return left;
}

std::unique_ptr<Expr> Parser::bitwise_and() {
    auto left = comparison();
    while (true) {
        skip_comments();
        if (!check(TokenType::AMP))
            break;
        advance();
        skip_comments();
        left = std::make_unique<BinaryExpr>('b', std::move(left), comparison());
    }
    return left;
}

static bool is_cmp_token(TokenType t) {
    return t == TokenType::GREATER || t == TokenType::LESS || t == TokenType::GREATER_EQUAL ||
           t == TokenType::LESS_EQUAL || t == TokenType::EQUAL_EQUAL || t == TokenType::NOT_EQUAL;
}
static char cmp_char(TokenType t) {
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
    skip_comments();
    if (!is_cmp_token(peek().type))
        return first;

    // collect all operands and operators
    auto chain = std::make_unique<ChainedCompareExpr>();
    chain->operands.push_back(std::move(first));
    while (is_cmp_token(peek().type)) {
        chain->ops.push_back(cmp_char(advance().type));
        skip_comments();
        chain->operands.push_back(shift());
        skip_comments();
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
        skip_comments();
        if (!check(TokenType::LSHIFT) && !check(TokenType::RSHIFT))
            break;
        char op = check(TokenType::LSHIFT) ? 'l' : 'r';
        advance();
        skip_comments();
        left = std::make_unique<BinaryExpr>(op, std::move(left), additive());
    }
    return left;
}

std::unique_ptr<Expr> Parser::additive() {
    auto left = multiplicative();
    while (true) {
        skip_comments();
        if (!check(TokenType::PLUS) && !check(TokenType::MINUS))
            break;
        char op = advance().lexeme[0];
        skip_comments();
        left = std::make_unique<BinaryExpr>(op, std::move(left), multiplicative());
    }
    return left;
}

std::unique_ptr<Expr> Parser::multiplicative() {
    auto left = unary();
    while (true) {
        skip_comments();
        if (!check(TokenType::STAR) && !check(TokenType::SLASH) && !check(TokenType::SLASH_SLASH) &&
            !check(TokenType::PERCENT))
            break;
        char op = check(TokenType::SLASH_SLASH) ? (advance(), 'q') : advance().lexeme[0];
        skip_comments();
        left = std::make_unique<BinaryExpr>(op, std::move(left), unary());
    }
    return left;
}

// `ref x` and `ref a.b.c`: pass by REFERENCE, desugared right here — no new type, no new
// opcode — into an object carrying the read and the write of the target:
//
//   {__ref: true, get: func() return x end, set: func(v) x = v end}
//
// The closures capture the target as an upvalue when it is local, and read or write the global
// otherwise: the upvalue machinery does all the work. `__ref` exists only so native modules can
// validate — a map with get/set is not necessarily a reference, the `data` module has some too.
static const char* REF_PARAM = "__ref_v";   // the setter's parameter name, which must not
                                            // must NEVER collide with the target (`ref v`)

std::unique_ptr<Expr> Parser::ref_expr() {
    int line = peek().line;
    advance(); // REF
    // Target: IDENT { "." IDENT }. Bracket indexing is refused, because the path is
    // re-evaluated on every access and `ref t[i]` would follow later changes to i.
    if (!check(TokenType::IDENTIFIER))
        throw std::runtime_error(cur_loc(line).str(*source_files_) + ": ref expects a variable name, not '" +
                                 peek().lexeme + "'");
    std::vector<std::string> path;
    path.push_back(advance().lexeme);
    while (check(TokenType::DOT)) {
        advance();
        path.push_back(expect(TokenType::IDENTIFIER).lexeme);
    }
    if (check(TokenType::LBRACKET))
        throw std::runtime_error(cur_loc(line).str(*source_files_) +
                                 ": ref only accepts a name or a path of fields, with no [] indexing");

    auto set_loc = [&](Expr* e) {
        e->line = line;
        e->file_idx = current_file_idx_;
    };
    // Builds the access to the first `n` segments (a VarExpr, or a chain of IndexExpr). Called
    // several times: each generated tree needs its own, since a unique_ptr cannot be copied.
    auto make_access = [&](size_t n) {
        std::unique_ptr<Expr> e = std::make_unique<VarExpr>(path[0]);
        set_loc(e.get());
        for (size_t i = 1; i < n; ++i) {
            auto ix = std::make_unique<IndexExpr>();
            ix->obj = std::move(e);
            auto k = std::make_unique<StringExpr>(path[i]);
            set_loc(k.get());
            ix->key = std::move(k);
            set_loc(ix.get());
            e = std::move(ix);
        }
        return e;
    };

    auto getter = std::make_unique<FuncExpr>();
    set_loc(getter.get());
    {
        auto ret = std::make_unique<ReturnStmt>();
        ret->line = line;
        ret->file_idx = current_file_idx_;
        ret->values.push_back(make_access(path.size()));
        getter->body.push_back(std::move(ret));
    }

    auto setter = std::make_unique<FuncExpr>();
    set_loc(setter.get());
    setter->params.push_back(REF_PARAM);
    setter->defaults.push_back(nullptr);
    {
        auto val = std::make_unique<VarExpr>(std::string(REF_PARAM));
        set_loc(val.get());
        std::unique_ptr<Stmt> assign;
        if (path.size() == 1) {
            auto a = std::make_unique<AssignStmt>();
            a->name = path[0];
            a->value = std::move(val);
            assign = std::move(a);
        } else {
            // a.b.c = v: the container is the access to `a.b`, the key is "c"
            auto ia = std::make_unique<IndexAssignStmt>();
            ia->obj_expr = make_access(path.size() - 1);
            auto k = std::make_unique<StringExpr>(path.back());
            set_loc(k.get());
            ia->key = std::move(k);
            ia->op = TokenType::EQUALS;
            ia->value = std::move(val);
            assign = std::move(ia);
        }
        assign->line = line;
        assign->file_idx = current_file_idx_;
        setter->body.push_back(std::move(assign));
    }

    auto m = std::make_unique<MapExpr>();
    set_loc(m.get());
    auto add = [&](const char* key, std::unique_ptr<Expr> value) {
        MapEntry e;
        auto k = std::make_unique<StringExpr>(std::string(key));
        set_loc(k.get());
        e.key = std::move(k);
        e.value = std::move(value);
        m->entries.push_back(std::move(e));
    };
    auto marker = std::make_unique<BoolExpr>(true);
    set_loc(marker.get());
    add("__ref", std::move(marker));
    add("get", std::move(getter));
    add("set", std::move(setter));
    return m;
}

// Precedence follows Lua: '^' binds tighter than unary minus.
//   multiplicative → unary → power → primary
//   -2 ^ 2 == -(2^2) == -4 ;  2 ^ -1 == 0.5 ;  2 ^ 2 ^ 3 == 2^(2^3) (right-associative)
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
    if (check(TokenType::REF))
        return ref_expr();
    return power();
}

std::unique_ptr<Expr> Parser::power() {
    auto left = primary();
    skip_comments();
    if (!check(TokenType::CARET))
        return left; // '^' is exponentiation, as in Lua
    advance();
    skip_comments();
    // A unary right operand allows 2 ^ -1, and right associativity gives 2^2^3.
    return std::make_unique<BinaryExpr>('p', std::move(left), unary());
}

std::unique_ptr<Expr> Parser::parse_postfix(std::unique_ptr<Expr> base) {
    while (check(TokenType::LBRACKET) || check(TokenType::DOT) || check(TokenType::LPAREN) ||
           (check(TokenType::QUESTION) && peek_next_type() == TokenType::LPAREN)) {
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
            bool opt_m = check(TokenType::QUESTION) && peek_next_type() == TokenType::LPAREN;
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
        } else { // LPAREN, or QUESTION+LPAREN for an optional call
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


// Scan forward from current position looking for SEMICOLON at depth 0 before
// COMMA or RBRACKET at depth 0. Returns true if this looks like a range.
bool Parser::looks_like_range() const {
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
std::unique_ptr<Expr> Parser::range_expr(bool incl_left) {
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
        throw std::runtime_error(peek().sloc().str(*source_files_) + ": expected ']' or '[' to close range");
    }

    // The open-left adjustment (incl_left = false, so start += step) is emitted by the
    // COMPILER from node->incl_left. Nothing to do here.
    return node;
}

std::unique_ptr<Expr> Parser::primary() {
    if (check(TokenType::NUMBER)) {
        Token tok = advance();
        const std::string& lex = tok.lexeme;
        try {
            // The lexeme is NORMALISED by the lexer: no '_', and the base prefix and the
            // exponent letter are lower case, so 'X'/'O'/'B'/'E' cannot appear here.
            // 0x.. / 0o.. / 0b..: integers in base 16/8/2 (stoull keeps the whole bit pattern, wrapping int64)
            if (lex.size() > 2 && lex[0] == '0' && lex[1] == 'x')
                return std::make_unique<NumberExpr>(static_cast<int64_t>(std::stoull(lex.substr(2), nullptr, 16)));
            if (lex.size() > 2 && lex[0] == '0' && lex[1] == 'o')
                return std::make_unique<NumberExpr>(static_cast<int64_t>(std::stoull(lex.substr(2), nullptr, 8)));
            if (lex.size() > 2 && lex[0] == '0' && lex[1] == 'b')
                return std::make_unique<NumberExpr>(static_cast<int64_t>(std::stoull(lex.substr(2), nullptr, 2)));
            // float on a '.' OR a scientific exponent; otherwise an integer.
            if (lex.find('.') == std::string::npos && lex.find('e') == std::string::npos)
                return std::make_unique<NumberExpr>(static_cast<int64_t>(std::stoll(lex)));
            return std::make_unique<NumberExpr>(std::stod(lex));
        } catch (const std::out_of_range&) {
            throw std::runtime_error(tok.sloc().str(*source_files_) + ": numeric literal out of range: " + lex);
        }
    }
    if (check(TokenType::STRING))
        return parse_postfix(std::make_unique<StringExpr>(advance().lexeme));
    if (check(TokenType::INTERP_START)) {
        auto node = std::make_unique<InterpExpr>();
        node->line = peek().line;
        node->file_idx = peek().file_idx;
        node->literals.push_back(advance().lexeme); // INTERP_START gives the first literal
        while (true) {
            node->exprs.push_back(expr());
            if (check(TokenType::INTERP_MID)) {
                node->literals.push_back(advance().lexeme);
            } else {
                Token end = expect(TokenType::INTERP_END);
                node->literals.push_back(end.lexeme);
                break;
            }
        }
        return parse_postfix(std::move(node));
    }
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
        // super.method(args): calls the parent method with the current self
        if (name == "super") {
            expect(TokenType::DOT);
            std::string method_name = expect(TokenType::IDENTIFIER).lexeme;
            bool opt_super = check(TokenType::QUESTION) && peek_next_type() == TokenType::LPAREN;
            if (opt_super)
                advance(); // consume '?'
            if (!check(TokenType::LPAREN))
                throw std::runtime_error(peek().sloc().str(*source_files_) +
                                         ": super: only method calls are supported");
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
            return parse_postfix(std::move(mc));
        }
        // Optional call F?(): calls only when F is callable, and yields nil otherwise.
        bool opt_call = check(TokenType::QUESTION) && peek_next_type() == TokenType::LPAREN;
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
            return parse_postfix(std::move(call));
        }
        // Plain variable — may be followed by postfix chaining
        return parse_postfix(std::make_unique<VarExpr>(name));
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
        consume_opt_comment();
        while (true) {
            skip_comments();
            if (check(TokenType::END) || check(TokenType::EOF_T))
                break;
            fe->body.push_back(parse_one_stmt());
        }
        expect(TokenType::END);
        return parse_postfix(std::move(fe));
    }
    if (check(TokenType::LBRACE)) {
        advance(); // consume {
        skip_comments();
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
                throw std::runtime_error(peek().sloc().str(*source_files_) +
                                         ": expected string, identifier, or [expr] key in map literal");
            }
            expect(TokenType::COLON);
            auto val = expr();
            map->entries.push_back({std::move(key), std::move(val)});
            if (check(TokenType::COMMA))
                advance();
            skip_comments();
        }
        expect(TokenType::RBRACE);
        return parse_postfix(std::move(map));
    }
    if (check(TokenType::LBRACKET)) {
        advance(); // consume [
        // Check if this is a range [a;b] or array [a,b,c]
        if (looks_like_range()) {
            return range_expr(true); // incl_left=true
        }
        skip_comments();
        auto arr = std::make_unique<ArrayExpr>();
        while (!check(TokenType::RBRACKET) && !check(TokenType::EOF_T)) {
            arr->elements.push_back(expr());
            if (check(TokenType::COMMA))
                advance();
            skip_comments();
        }
        expect(TokenType::RBRACKET);
        return parse_postfix(std::move(arr));
    }
    if (check(TokenType::RBRACKET)) {
        // Open-left range: ]a;b]  or  ]a;b[
        advance();               // consume ]
        return range_expr(false); // incl_left=false
    }
    if (match(TokenType::LPAREN)) {
        skip_comments();
        auto e = expr();
        skip_comments();
        expect(TokenType::RPAREN);
        // Postfix on a parenthesized expression: (expr)(args), (expr)[i], (expr).field
        return parse_postfix(std::move(e));
    }
    throw std::runtime_error(peek().sloc().str(*source_files_) + ": unexpected token '" + peek().lexeme + "'");
}

std::unique_ptr<Stmt> Parser::class_decl() {
    int line = peek().line;
    advance(); // CLASS
    auto s = std::make_unique<ClassDeclStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    s->name = expect(TokenType::IDENTIFIER).lexeme;
    if (check(TokenType::EXTENDS)) {
        advance();
        s->parent = expect(TokenType::IDENTIFIER).lexeme;
    }
    consume_opt_comment();
    while (true) {
        skip_comments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;
        bool is_static = false;
        if (check(TokenType::STATIC)) {
            advance();
            is_static = true;
        }
        if (!check(TokenType::FUNC))
            throw std::runtime_error(peek().sloc().str(*source_files_) + ": expected 'func' inside class body");
        int method_line = peek().line;
        // func_decl_stmt() returns an IndexAssignStmt for the `func obj.field()` form
        // which is invalid in a class. Check the type rather than static_cast'ing
        // blindly, which used to segfault.
        auto raw = func_decl_stmt();
        auto* fd = dynamic_cast<FuncDeclStmt*>(raw.get());
        if (!fd)
            throw std::runtime_error(cur_loc(method_line).str(*source_files_) +
                                     ": a class method must be 'func name(...)' (not 'func obj.field(...)')");
        raw.release();
        auto method = std::unique_ptr<FuncDeclStmt>(fd);
        method->is_static = is_static;
        s->methods.push_back(std::move(method));
    }
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

// Value of an integer literal, possibly preceded by '-': the only form that moves an enum's
// counter, since an arbitrary expression cannot be evaluated at compile time. Returns false
// when the expression is not one.
static bool enum_int_literal(const Expr* e, int64_t* out) {
    if (auto* u = dynamic_cast<const UnaryExpr*>(e)) {
        int64_t inner = 0;
        if (u->op == '-' && enum_int_literal(u->operand.get(), &inner)) {
            *out = -inner;
            return true;
        }
        return false;
    }
    auto* n = dynamic_cast<const NumberExpr*>(e);
    if (!n || !n->is_integer)
        return false;
    *out = n->ival;
    return true;
}

std::unique_ptr<Stmt> Parser::enum_decl() {
    int line = peek().line;
    advance(); // ENUM
    auto s = std::make_unique<EnumDeclStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;

    // Target: a plain name (a global) or a path `a.b.c` (a map field). Segments are read
    // first, the last one becomes `name` and the earlier ones fold into the container. We do
    // not call parse_postfix, which would also accept `a[0]` and `a.f()` — forms the grammar
    // does not allow as an enum target.
    std::vector<std::string> path;
    path.push_back(expect(TokenType::IDENTIFIER).lexeme);
    while (check(TokenType::DOT)) {
        advance();
        path.push_back(expect(TokenType::IDENTIFIER).lexeme);
    }
    s->name = path.back();
    path.pop_back();
    for (auto& seg : path) {
        if (!s->obj_expr) {
            s->obj_expr = std::make_unique<VarExpr>(seg);
        } else {
            auto ix = std::make_unique<IndexExpr>();
            ix->obj = std::move(s->obj_expr);
            ix->key = std::make_unique<StringExpr>(seg);
            s->obj_expr = std::move(ix);
        }
        s->obj_expr->line = line;
        s->obj_expr->file_idx = current_file_idx_;
    }

    int64_t counter = 1;   // the first item with no value is 1
    std::unordered_set<std::string> seen;
    while (true) {
        skip_comments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;
        EnumItem it;
        int item_line = peek().line;
        it.name = expect(TokenType::IDENTIFIER).lexeme;
        if (!seen.insert(it.name).second)
            throw std::runtime_error(cur_loc(item_line).str(*source_files_) + ": enum '" + s->name +
                                     "' : element '" + it.name + "' declared twice");
        if (check(TokenType::EQUALS)) {
            advance();
            it.value = expr();
            int64_t lit = 0;
            if (enum_int_literal(it.value.get(), &lit))
                counter = lit + 1;
        } else {
            it.value = std::make_unique<NumberExpr>((int64_t)counter++);
            it.value->line = item_line;
            it.value->file_idx = current_file_idx_;
        }
        s->items.push_back(std::move(it));
        skip_comments();
        if (check(TokenType::COMMA)) {
            advance();
            continue;
        }
        break;
    }
    skip_comments();
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

// Names a module exports, stored in the map of `import "m" as m`. Each kind of statement
// answers for itself (Stmt::exported_names, ast.h), so nothing here needs updating when the
// language gains a new declaring statement.
static std::vector<std::string> collect_top_level_names(const std::vector<std::unique_ptr<Stmt>>& stmts) {
    std::vector<std::string> names;
    for (auto& s : stmts)
        s->exported_names(names);
    return names;
}

std::unique_ptr<Stmt> Parser::import_stmt() {
    advance();
    Token path_tok = expect(TokenType::STRING);
    std::string path = path_tok.lexeme;
    if (path.size() < 3 || path.substr(path.size() - 3) != ".ol")
        path += ".ol";

    std::string alias;
    if (check(TokenType::AS)) {
        advance();
        alias = expect(TokenType::IDENTIFIER).lexeme;
    }
    consume_opt_comment();

    // Resolved against the importing file's directory, and normalised: this string IS the module's
    // identity (see paths.h).
    std::string resolved = path_resolve(base_dir_, path);

    auto block = std::make_unique<BlockStmt>();

    // Builds `var al = {}` then `al[n] = n` for every exported name, referencing the globals
    // already injected. Shared by the already-imported case and the fresh one.
    auto emit_alias_map = [&](const std::string& al, const std::vector<std::string>& names) {
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

    // Already imported (dedup, and cycle breaking): do NOT inject the statements again. When an
    // alias is asked for, rebuild its map from the names cached on the first import, otherwise a
    // second `import "m" as b` would yield an empty map.
    if (imported_paths_->count(resolved)) {
        if (!alias.empty()) {
            auto it = module_names_->find(resolved);
            emit_alias_map(alias, it != module_names_->end() ? it->second : std::vector<std::string>{});
        }
        return block;
    }
    imported_paths_->insert(resolved);

    // Read the imported file from the in-memory registry first (provided by the host, the WASM
    // playground for instance), then from disk.
    std::string src_text;
    if (!source_get(resolved, src_text) && !(resolved != path && source_get(path, src_text))) {
        std::ifstream f(resolved);
        if (!f)
            throw std::runtime_error(path_tok.sloc().str(*source_files_) + ": import: cannot open '" + resolved + "'");
        std::ostringstream ss;
        ss << f.rdbuf();
        src_text = ss.str();
    }

    std::string sub_dir = path_dir(resolved);

    // Register the imported file in the shared source table, then lex and parse with that
    // file_idx so tokens and AST nodes carry the right origin. The table is shared by every
    // parser in the chain.
    int sub_file_idx = (int)source_files_->size();
    source_files_->push_back(resolved);
    // Any error thrown from here already carries its own "file:line:" prefix, hence no catch.
    Parser sub_parser(Lexer(src_text, resolved, sub_file_idx).tokenize(), sub_dir, imported_paths_,
                      module_names_, source_files_);
    Program sub_prog = sub_parser.parse();

    // Remember the exported names even for a flat import, so a later aliased import of the same
    // module can rebuild its map.
    auto top_names = collect_top_level_names(sub_prog.stmts);
    (*module_names_)[resolved] = top_names;

    if (alias.empty()) {
        // Flat import: inject every statement directly.
        for (auto& s : sub_prog.stmts)
            block->stmts.push_back(std::move(s));
    } else {
        // Aliased import: var name = {}; <stmts>; name[k] = k for every top-level name.
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

std::unique_ptr<Stmt> Parser::switch_stmt() {
    int line = peek().line;
    advance(); // SWITCH
    auto s = std::make_unique<SwitchStmt>();
    s->line = line; s->file_idx = current_file_idx_;
    s->subject = expr();
    consume_opt_comment();

    auto is_arm_start = [&]() {
        return check(TokenType::CASE) || check(TokenType::ELSE) || check(TokenType::END) || check(TokenType::EOF_T);
    };

    while (true) {
        skip_comments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;

        if (check(TokenType::ELSE)) {
            advance(); // ELSE
            consume_opt_comment();
            while (!check(TokenType::END) && !check(TokenType::EOF_T)) {
                skip_comments();
                if (check(TokenType::END) || check(TokenType::EOF_T))
                    break;
                s->else_body.push_back(parse_one_stmt());
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
        consume_opt_comment();
        while (!is_arm_start()) {
            skip_comments();
            if (is_arm_start())
                break;
            arm.body.push_back(parse_one_stmt());
        }
        s->cases.push_back(std::move(arm));
    }

    expect(TokenType::END);
    consume_opt_comment();
    return s;
}
