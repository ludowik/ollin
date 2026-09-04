#include "parser.h"
#include "lexer.h"
#include "paths.h"
#include "source_registry.h"
#include <fstream>
#include <sstream>
#include <stdexcept>

Parser::Parser(std::vector<Token> tokens, std::string base_dir,
               std::shared_ptr<std::unordered_set<std::string>> imported,
               std::shared_ptr<std::unordered_map<std::string, std::vector<std::string>>> module_names,
               std::shared_ptr<std::vector<std::string>> source_files)
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

const Token& Parser::expect(TokenType t) {
    if (!check(t))
        fail("unexpected token '" + peek().lexeme + "'");
    return advance();
}

void Parser::fail(const std::string& msg) const {
    fail_at(peek().line, msg);
}

void Parser::fail_at(int line, const std::string& msg) const {
    throw std::runtime_error(cur_loc(line).str(*source_files_) + ": " + msg);
}

TokenType Parser::peek_next_type() const {
    if (pos + 1 < static_cast<int>(tokens.size()))
        return tokens[pos + 1].type;
    return TokenType::EOF_T;
}

// grammar.ebnf wants a plain NAME for a map-literal key and for a field after '.' — a word
// that happens to be a keyword ({end: 1}, m.in, ref cfg.class) is just that name. The lexer
// classifies by spelling alone and cannot know the position, so the decision belongs here.
// true/false/nil stay out on purpose: they carry a value, and turning them into strings
// silently would be a trap.
bool Parser::at_name() const {
    TokenType t = peek().type;
    if (t == TokenType::IDENTIFIER)
        return true;
    return is_keyword_type(t) && t != TokenType::TRUE && t != TokenType::FALSE && t != TokenType::NIL;
}

std::string Parser::expect_name(const char* what) {
    if (!at_name())
        fail(std::string("expected ") + what + ", got '" + peek().lexeme + "'");
    return advance().lexeme;
}

bool Parser::at_optional_call() const {
    return check(TokenType::QUESTION) && peek_next_type() == TokenType::LPAREN;
}

void Parser::skip_comments() {
    while (check(TokenType::COMMENT))
        advance();
}

// A token that ENDS a block, whichever block it is. The set lives here and nowhere else: written
// out a second time in return_stmt, it was missing CASE, so a bare 'return' as the last statement
// of a switch arm was refused.
bool Parser::at_block_terminator() const {
    switch (peek().type) {
    case TokenType::END:
    case TokenType::ELSE:
    case TokenType::ELSEIF:
    case TokenType::CATCH:
    case TokenType::CASE:
    case TokenType::EOF_T:
        return true;
    default:
        return false;
    }
}

void Parser::parse_body_until(std::vector<std::unique_ptr<Stmt>>& out, std::initializer_list<TokenType> stops) {
    while (true) {
        skip_comments();
        if (check(TokenType::EOF_T))
            return;
        for (TokenType t : stops)
            if (check(t))
                return;
        out.push_back(parse_one_stmt());
    }
}

void Parser::parse_params(std::vector<std::string>& params, std::vector<std::unique_ptr<Expr>>& defaults,
                          bool& variadic) {
    expect(TokenType::LPAREN);
    while (!check(TokenType::RPAREN) && !check(TokenType::EOF_T)) {
        if (match(TokenType::DOT_DOT_DOT)) {
            variadic = true;
            break;
        }
        params.push_back(expect(TokenType::IDENTIFIER).lexeme);
        defaults.push_back(match(TokenType::EQUALS) ? expr() : nullptr);
        if (!check(TokenType::RPAREN))
            expect(TokenType::COMMA);
    }
    expect(TokenType::RPAREN);
}

void Parser::parse_expr_list(std::vector<std::unique_ptr<Expr>>& out) {
    out.push_back(expr());
    while (match(TokenType::COMMA))
        out.push_back(expr());
}

void Parser::parse_call_args(std::vector<std::unique_ptr<Expr>>& out) {
    if (!check(TokenType::RPAREN))
        parse_expr_list(out);
    expect(TokenType::RPAREN);
}

// The comma between two items of a literal is MANDATORY, as grammar.ebnf says: newlines are not
// tokenized, so without it `[1 2 3]` quietly read as three elements and a forgotten comma changed
// the meaning of the program with no diagnostic. A comma before the closing bracket is allowed
// though — it is a real convenience of multi-line literals, and the samples use it.
void Parser::expect_separator(TokenType closing, const char* what) {
    if (match(TokenType::COMMA) || check(closing) || check(TokenType::EOF_T))
        return;
    fail(std::string("expected ',' between ") + what + ", got '" + peek().lexeme + "'");
}

void Parser::parse_field_path(std::vector<std::string>& path) {
    path.push_back(expect(TokenType::IDENTIFIER).lexeme);
    while (match(TokenType::DOT))
        path.push_back(expect_name("a field name"));
}

// Absorbs an optional COMMENT at the end of a statement. Statements are separated by
// newlines, which are not tokenized; there is no automatic semicolon insertion.
void Parser::consume_opt_comment() {
    match(TokenType::COMMENT);
}

// Stack-overflow guard: recursive descent (parentheses, calls, nested blocks) could crash the
// process on deeply nested input. Depth is bounded and a clean error is raised instead.
namespace {
// The counter is decremented on the way out; the depth is TESTED by the caller, which owns the
// location — formatting a "file:line" prefix for every statement and every expression, to serve
// a message that almost never fires, was paid on the hot path.
struct DepthGuard {
    int& d;
    explicit DepthGuard(int& depth) : d(depth) {
        ++d;
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
    prog.source_files = *source_files_; // the table grows with each import, hence the copy
    return prog;
}

static bool is_assign_op(TokenType t) {
    return t == TokenType::EQUALS || t == TokenType::PLUS_EQUAL || t == TokenType::MINUS_EQUAL ||
           t == TokenType::STAR_EQUAL || t == TokenType::SLASH_EQUAL || t == TokenType::PERCENT_EQUAL;
}

std::unique_ptr<Stmt> Parser::parse_one_stmt() {
    if (depth_ >= 256)
        fail("nesting too deep");
    DepthGuard guard(depth_);
    switch (peek().type) {
    case TokenType::COMMENT: {
        std::string text = advance().lexeme;
        consume_opt_comment();
        return std::make_unique<CommentStmt>(std::move(text));
    }
    case TokenType::SEMICOLON:
        // ';' is only valid inside a range [a;b], where range_expr consumes it. At statement
        // level it is an error, reported explicitly.
        fail("';' is not valid syntax — statements are terminated by newlines");
    case TokenType::LPAREN:
    case TokenType::LBRACKET:
        // A line that opens with a delimiter CONTINUES the expression above — that is what one
        // reads, and a continuation never reaches this point, being consumed by the previous
        // expression. Getting here therefore means there was nothing to continue, so the line
        // is a statement beginning with a delimiter: refused, since no statement does.
        fail(std::string("a statement cannot begin with '") + peek().lexeme +
             "' — such a line continues the expression above; give the value a name instead");
    case TokenType::WHILE:
        return while_stmt();
    case TokenType::DO:
        return do_stmt();
    case TokenType::IF:
        return if_stmt();
    case TokenType::BREAK:
        return break_stmt();
    case TokenType::CONTINUE:
        return continue_stmt();
    case TokenType::TRY:
        return try_catch_stmt();
    case TokenType::THROW:
        return throw_stmt();
    case TokenType::FOR:
        return for_stmt();
    case TokenType::IMPORT:
        return import_stmt();
    case TokenType::CLASS:
        return class_decl();
    case TokenType::ENUM:
        return enum_decl();
    case TokenType::SWITCH:
        return switch_stmt();
    case TokenType::FUNC:
        return func_decl_stmt();
    case TokenType::RETURN:
        return return_stmt();
    case TokenType::VAR:
        return decl_stmt(false, false);
    case TokenType::GLOBAL:
        return decl_stmt(true, false);
    case TokenType::CONSTANT:
        return decl_stmt(false, true);
    case TokenType::IDENTIFIER: {
        // A statement starting with an identifier is an assignment (plain, indexed or
        // chained), a multi-assignment, or an expression statement. We parse an expression and
        // decide from what follows: an assignment operator, a comma, or nothing. An assignment
        // target must be an lvalue (VarExpr or IndexExpr), which uniformly covers a=, a.b=,
        // a[i]=, a.b.c=, a[i][j]= and a.b[k]= (see the grammar).
        int line = peek().line;
        auto e = expr();
        if (is_assign_op(peek().type))
            return finish_assign_from_expr(std::move(e), line);
        if (check(TokenType::COMMA))
            return multi_assign_stmt(std::move(e), line);
        consume_opt_comment();
        auto st = std::make_unique<ExprStmt>(std::move(e));
        st->line = line;
        st->file_idx = current_file_idx_;
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
    TokenType opt = advance().type; // assignment operator
    auto value = expr();
    consume_opt_comment();
    if (auto* ve = dynamic_cast<VarExpr*>(target.get())) {
        auto s = std::make_unique<AssignStmt>();
        s->line = line;
        s->file_idx = current_file_idx_;
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
        s->file_idx = current_file_idx_;
        s->obj_expr = std::move(ie->obj); // the container, which may itself be chained
        s->key = std::move(ie->key);
        s->op = opt;
        s->value = std::move(value);
        return s;
    }
    fail_at(line, "invalid assignment target");
}

std::unique_ptr<Stmt> Parser::decl_stmt(bool is_global, bool is_constant) {
    int line = peek().line;
    advance(); // var / global / const
    auto s = std::make_unique<VarDeclStmt>();
    s->is_global = is_global;
    s->is_constant = is_constant;
    s->line = line;
    s->file_idx = current_file_idx_;
    s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    while (match(TokenType::COMMA))
        s->names.push_back(expect(TokenType::IDENTIFIER).lexeme);
    // A const MUST be initialized; without '=' a var or a global has no value, and the compiler
    // makes it nil.
    if (is_constant && !check(TokenType::EQUALS))
        fail_at(line, "const '" + s->names[0] + "' must be initialized");
    if (match(TokenType::EQUALS))
        parse_expr_list(s->values);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::while_stmt() {
    int line = peek().line;
    advance();
    auto s = std::make_unique<WhileStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;
    s->cond = expr();
    skip_comments();
    expect(TokenType::DO);
    parse_body_until(s->body, {TokenType::END});
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::do_stmt() {
    int line = peek().line;
    advance();
    auto s = std::make_unique<DoStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;
    parse_body_until(s->body, {TokenType::END});
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::if_stmt() {
    int line = peek().line;
    advance(); // IF
    auto s = std::make_unique<IfStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;
    s->cond = expr();
    skip_comments();
    expect(TokenType::THEN);
    parse_body_until(s->then_body, {TokenType::ELSE, TokenType::ELSEIF, TokenType::END});
    // There is no "else if" sugar: an elseif is spelled 'elseif'. An 'else' followed by an 'if'
    // is an else branch containing a nested if block, like any other statement.
    while (match(TokenType::ELSEIF)) {
        ElseIfClause ei;
        ei.cond = expr();
        skip_comments();
        expect(TokenType::THEN);
        parse_body_until(ei.body, {TokenType::ELSE, TokenType::ELSEIF, TokenType::END});
        s->else_ifs.push_back(std::move(ei));
    }
    if (match(TokenType::ELSE)) {
        consume_opt_comment();
        parse_body_until(s->else_body, {TokenType::END});
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
    s->line = line;
    s->file_idx = current_file_idx_;
    return s;
}

std::unique_ptr<Stmt> Parser::continue_stmt() {
    int line = peek().line;
    advance();
    consume_opt_comment();
    auto s = std::make_unique<ContinueStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;
    return s;
}

std::unique_ptr<Stmt> Parser::throw_stmt() {
    int line = peek().line;
    advance(); // throw
    auto s = std::make_unique<ThrowStmt>(expr());
    s->line = line;
    s->file_idx = current_file_idx_;
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::try_catch_stmt() {
    int line = peek().line;
    advance(); // try
    auto s = std::make_unique<TryCatchStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;
    consume_opt_comment();
    parse_body_until(s->try_body, {TokenType::CATCH});
    expect(TokenType::CATCH);
    s->catch_var = expect(TokenType::IDENTIFIER).lexeme;
    consume_opt_comment();
    parse_body_until(s->catch_body, {TokenType::ELSE, TokenType::END});
    if (match(TokenType::ELSE)) {
        consume_opt_comment();
        parse_body_until(s->else_body, {TokenType::END});
    }
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::func_decl_stmt() {
    int line = peek().line;
    advance(); // FUNC
    std::string name = expect(TokenType::IDENTIFIER).lexeme;
    // Definition on a map field: func obj.field(params) ... end
    // → desugared into  obj.field = func(params) ... end
    if (match(TokenType::DOT)) {
        std::string field = expect_name("a field name");
        auto fe = std::make_unique<FuncExpr>();
        parse_params(fe->params, fe->defaults, fe->variadic);
        consume_opt_comment();
        parse_body_until(fe->body, {TokenType::END});
        expect(TokenType::END);
        consume_opt_comment();
        auto ia = std::make_unique<IndexAssignStmt>();
        ia->line = line;
        ia->file_idx = current_file_idx_;
        ia->obj = std::move(name);
        ia->key = std::make_unique<StringExpr>(std::move(field));
        ia->op = TokenType::EQUALS;
        ia->value = std::move(fe);
        return ia;
    }
    return finish_func_decl(line, std::move(name));
}

std::unique_ptr<FuncDeclStmt> Parser::func_decl_named() {
    int line = peek().line;
    advance(); // FUNC
    std::string name = expect(TokenType::IDENTIFIER).lexeme;
    // The 'func obj.field()' form is a statement-level desugaring, so refusing it HERE keeps the
    // caller from having to recognise a foreign node type after the fact.
    if (check(TokenType::DOT))
        fail_at(line, "a class method must be 'func name(...)' (not 'func obj.field(...)')");
    return finish_func_decl(line, std::move(name));
}

std::unique_ptr<FuncDeclStmt> Parser::finish_func_decl(int line, std::string name) {
    auto s = std::make_unique<FuncDeclStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;
    s->name = std::move(name);
    parse_params(s->params, s->defaults, s->variadic);
    consume_opt_comment();
    parse_body_until(s->body, {TokenType::END});
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::return_stmt() {
    int line = peek().line;
    advance(); // RETURN
    auto s = std::make_unique<ReturnStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;
    // Return values are optional: none when we are on a block terminator, a separator or a
    // comment. A comment stands for the end of the line, newlines not being tokenized.
    if (!at_block_terminator() && !check(TokenType::SEMICOLON) && !check(TokenType::COMMENT)) {
        if (check(TokenType::DOT_DOT_DOT)) {
            advance();
            s->spread_varargs = true;
        } else {
            s->values.push_back(expr());
            while (match(TokenType::COMMA)) {
                if (match(TokenType::DOT_DOT_DOT)) {
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

// A target must be an lvalue: a name, or an indexing of any depth. Same rule as the single
// assignment, which reads it off the expression it has just parsed.
static bool is_lvalue(const Expr* e) {
    return dynamic_cast<const VarExpr*>(e) != nullptr || dynamic_cast<const IndexExpr*>(e) != nullptr;
}

std::unique_ptr<Stmt> Parser::multi_assign_stmt(std::unique_ptr<Expr> first, int line) {
    auto s = std::make_unique<MultiAssignStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;

    s->targets.push_back(std::move(first));
    while (match(TokenType::COMMA))
        s->targets.push_back(expr());
    for (auto& t : s->targets)
        if (!is_lvalue(t.get()))
            fail_at(line, "invalid assignment target");

    expect(TokenType::EQUALS);
    parse_expr_list(s->values);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::for_stmt() {
    int line = peek().line;
    advance(); // FOR
    std::string first_var = expect(TokenType::IDENTIFIER).lexeme;

    std::string var2;
    std::unique_ptr<Expr> iter_e;
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
        iter_e = std::move(range);
    } else {
        // for var1[, var2] in expr
        if (match(TokenType::COMMA))
            var2 = expect(TokenType::IDENTIFIER).lexeme;
        expect(TokenType::IN);
        iter_e = expr();
    }

    skip_comments();
    expect(TokenType::DO);
    auto s = std::make_unique<ForIterStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;
    s->var1 = std::move(first_var);
    s->var2 = std::move(var2);
    s->iter_expr = std::move(iter_e);
    parse_body_until(s->body, {TokenType::END});
    expect(TokenType::END);
    consume_opt_comment();
    return s;
}

std::unique_ptr<Stmt> Parser::expr_stmt() {
    int line = peek().line;
    auto e = expr();
    consume_opt_comment();
    auto s = std::make_unique<ExprStmt>(std::move(e));
    s->line = line;
    s->file_idx = current_file_idx_;
    return s;
}

std::unique_ptr<Expr> Parser::expr() {
    if (depth_ >= 256)
        fail("nesting too deep");
    DepthGuard guard(depth_);
    return binary_level(0);
}

namespace {
struct BinOp {
    TokenType tok;
    char op; // the code BinaryExpr uses (see compiler.cpp, token_to_op)
};
// One entry per PRECEDENCE level, loosest first. Levels 0..4 sit above the comparison, levels
// 5..7 below it — the comparison being chainable (a < b < c), it is a shape of its own and keeps
// its own function. Adding an operator is one line here instead of a new near-identical method.
struct BinLevel {
    const BinOp* ops;
    int n;
};
const BinOp OPS_OR[] = {{TokenType::OR, '|'}};
const BinOp OPS_AND[] = {{TokenType::AND, '&'}};
const BinOp OPS_BOR[] = {{TokenType::PIPE, 'o'}};
const BinOp OPS_BXOR[] = {{TokenType::TILDE, 'x'}}; // a binary '~' is XOR, as in Lua
const BinOp OPS_BAND[] = {{TokenType::AMP, 'b'}};
const BinOp OPS_SHIFT[] = {{TokenType::LSHIFT, 'l'}, {TokenType::RSHIFT, 'r'}};
const BinOp OPS_ADD[] = {{TokenType::PLUS, '+'}, {TokenType::MINUS, '-'}};
const BinOp OPS_MUL[] = {
    {TokenType::STAR, '*'}, {TokenType::SLASH, '/'}, {TokenType::SLASH_SLASH, 'q'}, {TokenType::PERCENT, '%'}};
#define LEVEL(a)                                                                                                       \
    { a, (int)(sizeof(a) / sizeof(*a)) }
// The comparison HOLDS ITS RANK in the table, as an empty entry: leaving it out made the level
// numbers of the two halves disagree, and the shift level was then skipped entirely.
const BinLevel LEVELS[] = {LEVEL(OPS_OR), LEVEL(OPS_AND),   LEVEL(OPS_BOR), LEVEL(OPS_BXOR), LEVEL(OPS_BAND),
                           {nullptr, 0},  LEVEL(OPS_SHIFT), LEVEL(OPS_ADD), LEVEL(OPS_MUL)};
#undef LEVEL
const int CMP_LEVEL = 5;
const int N_LEVELS = (int)(sizeof(LEVELS) / sizeof(*LEVELS));
} // namespace

std::unique_ptr<Expr> Parser::binary_level(int level) {
    if (level == CMP_LEVEL)
        return comparison();
    if (level == N_LEVELS)
        return unary();
    const BinLevel& lv = LEVELS[level];
    auto left = binary_level(level + 1);
    while (true) {
        skip_comments();
        const BinOp* found = nullptr;
        for (int i = 0; i < lv.n && !found; i++)
            if (check(lv.ops[i].tok))
                found = &lv.ops[i];
        if (!found)
            return left;
        advance();
        skip_comments();
        left = std::make_unique<BinaryExpr>(found->op, std::move(left), binary_level(level + 1));
    }
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
    auto first = binary_level(CMP_LEVEL + 1);
    skip_comments();
    if (!is_cmp_token(peek().type))
        return first;

    // A single comparison is a plain BinaryExpr; the chained node is only built from the SECOND
    // operator on, so the common case allocates nothing extra.
    char op1 = cmp_char(advance().type);
    skip_comments();
    auto second = binary_level(CMP_LEVEL + 1);
    skip_comments();
    if (!is_cmp_token(peek().type))
        return std::make_unique<BinaryExpr>(op1, std::move(first), std::move(second));

    auto chain = std::make_unique<ChainedCompareExpr>();
    chain->ops.push_back(op1);
    chain->operands.push_back(std::move(first));
    chain->operands.push_back(std::move(second));
    while (is_cmp_token(peek().type)) {
        chain->ops.push_back(cmp_char(advance().type));
        skip_comments();
        chain->operands.push_back(binary_level(CMP_LEVEL + 1));
        skip_comments();
    }
    return chain;
}

// Folds the first `n` segments of a path into a VarExpr followed by a chain of IndexExpr —
// what `a.b.c` means. Called several times per `ref` (a unique_ptr cannot be copied) and once
// per enum target, which is why it is not a lambda of either.
static std::unique_ptr<Expr> fold_path(const std::vector<std::string>& path, size_t n, SourceLoc loc) {
    std::unique_ptr<Expr> e = std::make_unique<VarExpr>(path[0]);
    e->line = loc.line;
    e->file_idx = loc.file_idx;
    for (size_t i = 1; i < n; ++i) {
        auto ix = std::make_unique<IndexExpr>();
        ix->obj = std::move(e);
        auto k = std::make_unique<StringExpr>(path[i]);
        k->line = loc.line;
        k->file_idx = loc.file_idx;
        ix->key = std::move(k);
        ix->line = loc.line;
        ix->file_idx = loc.file_idx;
        e = std::move(ix);
    }
    return e;
}

// `ref x` and `ref a.b.c`: pass by REFERENCE, desugared right here — no new type, no new
// opcode — into an object carrying the read and the write of the target:
//
//   {__ref: true, get: func() return x end, set: func(v) x = v end}
//
// The closures capture the target as an upvalue when it is local, and read or write the global
// otherwise: the upvalue machinery does all the work. `__ref` exists only so native modules can
// validate — a map with get/set is not necessarily a reference, the `data` module has some too.
static const char* REF_PARAM = "__ref_v"; // the setter's parameter name, which must not
                                          // must NEVER collide with the target (`ref v`)

std::unique_ptr<Expr> Parser::ref_expr() {
    int line = peek().line;
    advance(); // REF
    // Target: IDENT { "." IDENT }. Bracket indexing is refused, because the path is
    // re-evaluated on every access and `ref t[i]` would follow later changes to i.
    if (!check(TokenType::IDENTIFIER))
        fail_at(line, "ref expects a variable name, not '" + peek().lexeme + "'");
    std::vector<std::string> path;
    parse_field_path(path);
    if (check(TokenType::LBRACKET))
        fail_at(line, "ref only accepts a name or a path of fields, with no [] indexing");

    auto set_loc = [&](Expr* e) {
        e->line = line;
        e->file_idx = current_file_idx_;
    };
    auto make_access = [&](size_t n) { return fold_path(path, n, cur_loc(line)); };

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
    if (match(TokenType::HASH)) {
        // A real unary operator, NOT a call to `len` by name: resolved in the user's scope, a
        // `var len = 5` used to intercept '#' and the program failed with "call on non-function
        // value". The same hygiene as REF_PARAM below.
        return std::make_unique<UnaryExpr>('#', unary());
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
    while (check(TokenType::LBRACKET) || check(TokenType::DOT) || check(TokenType::LPAREN) || at_optional_call()) {
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
            std::string field = expect_name("a field name");
            bool opt_m = at_optional_call();
            if (check(TokenType::LPAREN) || opt_m) {
                if (opt_m)
                    advance(); // consume '?'
                advance();     // consume LPAREN
                auto mc = std::make_unique<MethodCallExpr>();
                mc->receiver = std::move(base);
                mc->method = std::move(field);
                mc->is_super = false;
                mc->optional = opt_m;
                parse_call_args(mc->args);
                base = std::move(mc);
            } else {
                auto ie = std::make_unique<IndexExpr>();
                ie->obj = std::move(base);
                ie->key = std::make_unique<StringExpr>(std::move(field));
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
            parse_call_args(call->args);
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

    node->start = expr();

    expect(TokenType::SEMICOLON);

    node->end = expr();

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
        fail("expected ']' or '[' to close range");
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
            // 0x / 0o / 0b: an integer in base 16/8/2 (stoull keeps the whole bit pattern,
            // wrapping int64). One conversion for the three bases, read from the prefix.
            int base = lex.size() > 2 && lex[0] == '0' ? (lex[1] == 'x'   ? 16
                                                          : lex[1] == 'o' ? 8
                                                          : lex[1] == 'b' ? 2
                                                                          : 0)
                                                       : 0;
            if (base)
                return std::make_unique<NumberExpr>(static_cast<int64_t>(std::stoull(lex.c_str() + 2, nullptr, base)));
            // float on a '.' OR a scientific exponent; otherwise an integer.
            if (lex.find('.') == std::string::npos && lex.find('e') == std::string::npos)
                return std::make_unique<NumberExpr>(static_cast<int64_t>(std::stoll(lex)));
            return std::make_unique<NumberExpr>(std::stod(lex));
        } catch (const std::out_of_range&) {
            fail_at(tok.line, "numeric literal out of range: " + lex);
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
            std::string method_name = expect_name("a method name");
            bool opt_super = at_optional_call();
            if (opt_super)
                advance(); // consume '?'
            if (!check(TokenType::LPAREN))
                fail("super: only method calls are supported");
            advance(); // LPAREN
            auto mc = std::make_unique<MethodCallExpr>();
            mc->receiver = nullptr;
            mc->method = std::move(method_name);
            mc->is_super = true;
            mc->optional = opt_super;
            parse_call_args(mc->args);
            return parse_postfix(std::move(mc));
        }
        // Optional call F?(): calls only when F is callable, and yields nil otherwise.
        bool opt_call = at_optional_call();
        if (opt_call)
            advance(); // consume '?'
        if (match(TokenType::LPAREN)) {
            auto call = std::make_unique<CallExpr>();
            call->callee = name;
            call->optional = opt_call;
            parse_call_args(call->args);
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
        parse_params(fe->params, fe->defaults, fe->variadic);
        consume_opt_comment();
        parse_body_until(fe->body, {TokenType::END});
        expect(TokenType::END);
        return parse_postfix(std::move(fe));
    }
    if (check(TokenType::LBRACE)) {
        advance(); // consume {
        skip_comments();
        auto map = std::make_unique<MapExpr>();
        while (!check(TokenType::RBRACE) && !check(TokenType::EOF_T)) {
            std::unique_ptr<Expr> key;
            if (check(TokenType::STRING) || at_name()) {
                key = std::make_unique<StringExpr>(advance().lexeme);
            } else if (check(TokenType::LBRACKET)) {
                advance();
                key = expr();
                expect(TokenType::RBRACKET);
            } else {
                fail("expected string, identifier, or [expr] key in map literal");
            }
            expect(TokenType::COLON);
            auto val = expr();
            map->entries.push_back({std::move(key), std::move(val)});
            expect_separator(TokenType::RBRACE, "map entries");
            skip_comments();
        }
        expect(TokenType::RBRACE);
        return parse_postfix(std::move(map));
    }
    if (check(TokenType::LBRACKET)) {
        advance();
        if (looks_like_range()) {
            return range_expr(true); // incl_left=true
        }
        skip_comments();
        auto arr = std::make_unique<ArrayExpr>();
        while (!check(TokenType::RBRACKET) && !check(TokenType::EOF_T)) {
            arr->elements.push_back(expr());
            expect_separator(TokenType::RBRACKET, "array elements");
            skip_comments();
        }
        expect(TokenType::RBRACKET);
        return parse_postfix(std::move(arr));
    }
    if (check(TokenType::RBRACKET)) {
        // Open-left range: ]a;b]  or  ]a;b[
        advance();                // consume ]
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
    fail("unexpected token '" + peek().lexeme + "'");
}

std::unique_ptr<Stmt> Parser::class_decl() {
    int line = peek().line;
    advance(); // CLASS
    auto s = std::make_unique<ClassDeclStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;
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
            fail("expected 'func' inside class body");
        auto method = func_decl_named();
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
    parse_field_path(path);
    s->name = path.back();
    if (path.size() > 1)
        s->obj_expr = fold_path(path, path.size() - 1, cur_loc(line));

    int64_t counter = 1; // the first item with no value is 1
    std::unordered_set<std::string> seen;
    while (true) {
        skip_comments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;
        EnumItem it;
        int item_line = peek().line;
        it.name = expect(TokenType::IDENTIFIER).lexeme;
        if (!seen.insert(it.name).second)
            fail_at(item_line, "enum '" + s->name + "' : element '" + it.name + "' declared twice");
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
        if (!match(TokenType::COMMA))
            break;
    }
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
    const Token& path_tok = expect(TokenType::STRING);
    int path_line = path_tok.line;
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

    // `var al = {}` and `al[n] = n` for every exported name, referencing the globals already
    // injected. TWO halves and not one: a fresh import must slip the module's statements
    // BETWEEN them, and the second copy written for that case is what made this lambda a lie.
    auto emit_alias_decl = [&](const std::string& al) {
        auto vd = std::make_unique<VarDeclStmt>();
        vd->line = path_line;
        vd->file_idx = current_file_idx_;
        vd->import_alias_of = resolved; // two importers of the same module may both declare it
        vd->names.push_back(al);
        vd->values.push_back(std::make_unique<MapExpr>());
        block->stmts.push_back(std::move(vd));
    };
    auto emit_alias_fields = [&](const std::string& al, const std::vector<std::string>& names) {
        for (auto& tname : names) {
            auto ia = std::make_unique<IndexAssignStmt>();
            ia->line = path_line;
            ia->file_idx = current_file_idx_;
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
    if (!imported_paths_->insert(resolved).second) {
        if (!alias.empty()) {
            static const std::vector<std::string> none;
            auto it = module_names_->find(resolved);
            emit_alias_decl(alias);
            emit_alias_fields(alias, it != module_names_->end() ? it->second : none);
        }
        return block;
    }

    // Read the imported file from the in-memory registry first (provided by the host, the WASM
    // playground for instance), then from disk.
    std::string src_text;
    if (!source_get(resolved, src_text) && !(resolved != path && source_get(path, src_text))) {
        std::ifstream f(resolved);
        if (!f)
            fail_at(path_line, "import: cannot open '" + resolved + "'");
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
    Parser sub_parser(Lexer(src_text, resolved, sub_file_idx).tokenize(), sub_dir, imported_paths_, module_names_,
                      source_files_);
    Program sub_prog = sub_parser.parse();

    // Remember the exported names even for a flat import, so a later aliased import of the same
    // module can rebuild its map.
    const std::vector<std::string>& top_names = (*module_names_)[resolved] = collect_top_level_names(sub_prog.stmts);

    // Aliased import: var name = {}; <stmts>; name[k] = k for every top-level name.
    if (!alias.empty())
        emit_alias_decl(alias);
    for (auto& st : sub_prog.stmts)
        block->stmts.push_back(std::move(st));
    if (!alias.empty())
        emit_alias_fields(alias, top_names);
    return block;
}

std::unique_ptr<Stmt> Parser::switch_stmt() {
    int line = peek().line;
    advance(); // SWITCH
    auto s = std::make_unique<SwitchStmt>();
    s->line = line;
    s->file_idx = current_file_idx_;
    s->subject = expr();
    consume_opt_comment();

    while (true) {
        skip_comments();
        if (check(TokenType::END) || check(TokenType::EOF_T))
            break;

        if (match(TokenType::ELSE)) {
            consume_opt_comment();
            parse_body_until(s->else_body, {TokenType::END});
            break;
        }

        expect(TokenType::CASE);
        CaseClause arm;
        parse_expr_list(arm.values);
        consume_opt_comment();
        parse_body_until(arm.body, {TokenType::CASE, TokenType::ELSE, TokenType::END});
        s->cases.push_back(std::move(arm));
    }

    expect(TokenType::END);
    consume_opt_comment();
    return s;
}
