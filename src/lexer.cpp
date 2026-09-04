#include "lexer.h"
#include "robin_hood.h"
#include "utf8.h"
#include <cstdint>
#include <stdexcept>
#include <string>

// ASCII predicates rather than <cctype>: the syntax of the language must not depend on the
// locale (isalnum can accept bytes >= 0x80, which would change how identifiers are split).
static inline bool is_dec(char c) {
    return c >= '0' && c <= '9';
}
static inline bool is_hex(char c) {
    return is_dec(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}
static inline bool is_alpha(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}
static inline bool is_alnum(char c) {
    return is_alpha(c) || is_dec(c);
}

static const robin_hood::unordered_map<std::string, TokenType> s_keywords = {
    {"var", TokenType::VAR},         {"global", TokenType::GLOBAL},
    {"const", TokenType::CONSTANT},  {"while", TokenType::WHILE},
    {"do", TokenType::DO},           {"if", TokenType::IF},
    {"then", TokenType::THEN},       {"end", TokenType::END},
    {"break", TokenType::BREAK},     {"continue", TokenType::CONTINUE},
    {"true", TokenType::TRUE},       {"false", TokenType::FALSE},
    {"try", TokenType::TRY},         {"catch", TokenType::CATCH},
    {"throw", TokenType::THROW},     {"else", TokenType::ELSE},
    {"elseif", TokenType::ELSEIF},   {"func", TokenType::FUNC},
    {"return", TokenType::RETURN},   {"nil", TokenType::NIL},
    {"or", TokenType::OR},           {"and", TokenType::AND},
    {"not", TokenType::NOT},         {"for", TokenType::FOR},
    {"in", TokenType::IN},           {"import", TokenType::IMPORT},
    {"as", TokenType::AS},           {"class", TokenType::CLASS},
    {"extends", TokenType::EXTENDS}, {"static", TokenType::STATIC},
    {"switch", TokenType::SWITCH},   {"case", TokenType::CASE},
    {"enum", TokenType::ENUM},       {"ref", TokenType::REF},
};

Lexer::Lexer(std::string source, std::string filename, int file_idx)
    : src(std::move(source)), filename_(std::move(filename)), file_idx_(file_idx), len_(static_cast<int>(src.size())) {
}

char Lexer::peek() const {
    return at_end() ? '\0' : src[pos];
}
char Lexer::advance() {
    return src[pos++];
}
bool Lexer::at_end() const {
    return pos >= len_;
}
bool Lexer::match(char c) {
    if (peek() != c)
        return false;
    pos++;
    return true;
}

void Lexer::fail(const std::string& msg, int at_line) const {
    throw std::runtime_error(filename_ + ":" + std::to_string(at_line) + ": " + msg);
}

void Lexer::emit(std::vector<Token>& out, Token t) const {
    t.file_idx = file_idx_;
    out.push_back(std::move(t));
}

void Lexer::skip_whitespace() {
    while (true) {
        char c = peek();
        if (c != ' ' && c != '\t' && c != '\r')
            return;
        advance();
    }
}

Token Lexer::number(bool leading_dot) {
    int start = pos - 1;
    std::string digits;
    bool dot_seen = leading_dot;
    if (leading_dot)
        digits += '.';
    else
        digits += src[start];

    // Hex (0x..), octal (0o..) and binary (0b..) integer literals. '_' is allowed only
    // between two digits (see grammar.ebnf). The prefix letter is normalised to lower case
    // here, so the parser never sees '0X'/'0O'/'0B'.
    if (!leading_dot && src[start] == '0') {
        char pl = peek() == 'x' || peek() == 'X'   ? 'x'
                  : peek() == 'o' || peek() == 'O' ? 'o'
                  : peek() == 'b' || peek() == 'B' ? 'b'
                                                   : '\0';
        if (pl != '\0') {
            const char* kind = pl == 'x' ? "hexadecimal" : pl == 'o' ? "octal" : "binary";
            auto invalid = [&]() { fail(std::string("invalid ") + kind + " literal", line); };
            advance();
            digits += pl;
            auto is_base_digit = [pl](char c) {
                if (pl == 'x')
                    return is_hex(c);
                if (pl == 'o')
                    return c >= '0' && c <= '7';
                return c == '0' || c == '1';
            };
            bool last_was_digit = false;
            while (!at_end()) {
                char c = peek();
                if (c == '_') {
                    if (!last_was_digit)
                        break; // a leading or doubled '_' is invalid
                    advance();
                    last_was_digit = false;
                    continue;
                }
                if (!is_base_digit(c))
                    break;
                advance();
                digits += c;
                last_was_digit = true;
            }
            // no digit or a trailing underscore, then an alphanumeric / '.' stuck to the end
            if (!last_was_digit)
                invalid();
            if (is_alnum(peek()) || peek() == '.')
                invalid();
            return {TokenType::NUMBER, digits, line};
        }
    }

    // Decimal: '_' only between digits, a single '.', nothing alphanumeric stuck to the end.
    bool last_was_digit = !leading_dot; // src[start] is a digit when !leading_dot
    bool prev_underscore = false;
    while (!at_end()) {
        char c = peek();
        if (is_dec(c)) {
            advance();
            digits += c;
            last_was_digit = true;
            prev_underscore = false;
        } else if (c == '_' && last_was_digit) {
            advance();
            last_was_digit = false;
            prev_underscore = true; // it must be followed by a digit
        } else if (c == '.' && !dot_seen && !prev_underscore) {
            advance();
            dot_seen = true;
            digits += '.';
            last_was_digit = false;
        } else {
            break;
        }
    }
    // Optional scientific exponent, [eE] [+-]? digits, which makes the number a float. The
    // 'e' is normalised to lower case, as the base prefixes are.
    if (peek() == 'e' || peek() == 'E') {
        if (prev_underscore) // a '_' right before the exponent is invalid (e.g. 1_e5)
            fail("invalid number literal", line);
        digits += 'e';
        advance();
        if (peek() == '+' || peek() == '-')
            digits += advance();
        bool exp_digit = false;
        while (is_dec(peek())) {
            digits += advance();
            exp_digit = true;
        }
        if (!exp_digit) // an 'e' with no digit (1e, 1e+)
            fail("invalid number literal", line);
    }
    // trailing '_' (or one not followed by a digit), or an alphanumeric / '.' / '_' stuck to the end
    if (prev_underscore || is_alnum(peek()) || peek() == '.' || peek() == '_')
        fail("invalid number literal", line);
    return {TokenType::NUMBER, digits, line};
}

// POSITIONAL slot vs interpolated expression: positional when the prefix (up to the first
// ':') is empty or all digits — {}, {0}, {1:.3f}, {:.3f}. Those braces stay LITERAL in the
// string and are filled in by printf; any other form ({x}, {a+b}, {x:.3f}) is an expression.
static bool is_positional_placeholder(const std::string& s) {
    auto blank = [](char c) { return c == ' ' || c == '\t' || c == '\r'; };
    size_t i = 0;
    while (i < s.size() && blank(s[i]))
        i++;
    while (i < s.size() && is_dec(s[i]))
        i++;
    while (i < s.size() && blank(s[i]))
        i++;
    return i == s.size() || s[i] == ':';
}

void Lexer::interp_string(std::vector<Token>& out) {
    int str_line = line;
    std::string literal;
    bool has_interp = false;

    while (true) {
        // Everything up to the next character of interest is copied in one block: a plain
        // string, which is the common case, costs a single append.
        size_t stop = src.find_first_of("\"\n{\\", (size_t)pos);
        if (stop == std::string::npos)
            stop = src.size();
        literal.append(src, (size_t)pos, stop - (size_t)pos);
        pos = (int)stop;
        if (at_end() || peek() == '"' || peek() == '\n')
            break;

        if (advance() == '\\') { // only '\{' is an escape here; any other '\' stays literal
            literal += match('{') ? '{' : '\\';
            continue;
        }

        // Capture the {…} content (nested braces and strings) WITHOUT emitting anything: we
        // must first decide between a positional slot and an interpolated expression. The
        // top-level ':' that separates the expression from its format spec is spotted in the
        // SAME pass, so the two depth rules are written once — a map literal {a:1} and an
        // index t[a:b] both nest, hence the two counters.
        int depth = 1;    // braces: it is this one that ends the capture
        int brackets = 0; // parens and square brackets, for the top-level ':' only
        int inner_start = pos;
        int spec_at = -1;
        while (!at_end() && depth > 0) {
            char ec = peek();
            if (ec == '\n')
                break;
            if (ec == '"') {
                advance();
                while (!at_end() && peek() != '"' && peek() != '\n')
                    advance();
                match('"');
                continue;
            }
            if (ec == '{')
                depth++;
            else if (ec == '}' && --depth == 0)
                break;
            else if (ec == '(' || ec == '[')
                brackets++;
            else if (ec == ')' || ec == ']')
                brackets--;
            else if (ec == ':' && depth == 1 && brackets == 0 && spec_at < 0)
                spec_at = pos;
            advance();
        }
        if (depth > 0) // end of source or newline before the closing brace
            fail("unclosed brace in interpolation", str_line);

        std::string inner = src.substr(inner_start, pos - inner_start);
        advance(); // consumes '}'

        // Positional ({}, {0}, {1:.3f}): left literal, filled in by printf.
        if (is_positional_placeholder(inner)) {
            literal += '{';
            literal += inner;
            literal += '}';
            continue;
        }

        std::string expr_src = spec_at < 0 ? inner : inner.substr(0, spec_at - inner_start);
        std::string spec = spec_at < 0 ? std::string() : inner.substr(spec_at - inner_start + 1);

        emit(out, {has_interp ? TokenType::INTERP_MID : TokenType::INTERP_START, literal, str_line});
        has_interp = true;
        literal.clear();

        auto emit_sub = [&](std::string code) {
            Lexer sub(std::move(code), filename_, file_idx_);
            sub.line = str_line;
            for (auto& t : sub.tokenize())
                if (t.type != TokenType::EOF_T)
                    emit(out, std::move(t));
        };

        if (spec.empty()) {
            emit_sub(std::move(expr_src));
        } else {
            // Desugaring: {expr:spec} becomes __fmt(expr, "spec"), the shared formatter.
            emit(out, {TokenType::IDENTIFIER, "__fmt", str_line});
            emit(out, {TokenType::LPAREN, "(", str_line});
            emit_sub(std::move(expr_src));
            emit(out, {TokenType::COMMA, ",", str_line});
            emit(out, {TokenType::STRING, spec, str_line});
            emit(out, {TokenType::RPAREN, ")", str_line});
        }
    }

    if (at_end() || peek() == '\n')
        fail("unterminated string", str_line);
    advance(); // consumes '"'

    emit(out, {has_interp ? TokenType::INTERP_END : TokenType::STRING, literal, str_line});
}

Token Lexer::identifier() {
    int start = pos - 1;
    while (is_alnum(peek()) || peek() == '_')
        advance();
    std::string lex = src.substr(start, pos - start);
    auto it = s_keywords.find(lex);
    return {it != s_keywords.end() ? it->second : TokenType::IDENTIFIER, lex, line};
}

Token Lexer::comment() {
    int start = pos;
    while (!at_end() && peek() != '\n')
        advance();
    return {TokenType::COMMENT, src.substr(start, pos - start), line};
}

Token Lexer::block_comment() {
    int start = pos;
    int hashes = 0;
    while (!at_end()) {
        char c = advance();
        if (c == '\n')
            line++;
        hashes = (c == '#') ? hashes + 1 : 0;
        if (hashes == 3)
            break;
    }
    if (hashes < 3)
        fail("unterminated block comment", line);
    return {TokenType::COMMENT, src.substr(start, pos - start - 3), line};
}

std::vector<Token> Lexer::tokenize() {
    std::vector<Token> tokens;
    tokens.reserve(src.size() / 4 + 8); // a prudent estimate: it only avoids reallocations

    for (;;) {
        skip_whitespace();
        if (at_end())
            break;

        char c = advance();
        switch (c) {
        case '\n':
            line++;
            break;
        case '=':
            emit(tokens, match('=') ? Token{TokenType::EQUAL_EQUAL, "==", line} : Token{TokenType::EQUALS, "=", line});
            break;
        case ',':
            emit(tokens, {TokenType::COMMA, ",", line});
            break;
        case '(':
            emit(tokens, {TokenType::LPAREN, "(", line});
            break;
        case ')':
            emit(tokens, {TokenType::RPAREN, ")", line});
            break;
        case '.':
            if (match('.')) {
                if (!match('.'))
                    fail("'..' is not valid syntax (use [a;b] for ranges)", line);
                emit(tokens, {TokenType::DOT_DOT_DOT, "...", line});
            } else if (is_dec(peek())) {
                emit(tokens, number(true)); // .5 is a decimal number
            } else {
                emit(tokens, {TokenType::DOT, ".", line});
            }
            break;
        case ';':
            // Always emitted: the range separator [a;b] needs it, including for left-open
            // ranges ]a;b] where a bracket counter cannot tell opening from closing. A ';'
            // outside a range is rejected by the parser, which reports it per statement.
            emit(tokens, {TokenType::SEMICOLON, ";", line});
            break;
        case '+':
            emit(tokens, match('=') ? Token{TokenType::PLUS_EQUAL, "+=", line} : Token{TokenType::PLUS, "+", line});
            break;
        case '-':
            emit(tokens, match('=') ? Token{TokenType::MINUS_EQUAL, "-=", line} : Token{TokenType::MINUS, "-", line});
            break;
        case '*':
            if (match('='))
                emit(tokens, {TokenType::STAR_EQUAL, "*=", line});
            else if (peek() == '*')
                fail("'**' no longer exists — use '^' for exponentiation", line);
            else
                emit(tokens, {TokenType::STAR, "*", line});
            break;
        case '/':
            if (match('='))
                emit(tokens, {TokenType::SLASH_EQUAL, "/=", line});
            else
                emit(tokens,
                     match('/') ? Token{TokenType::SLASH_SLASH, "//", line} : Token{TokenType::SLASH, "/", line});
            break;
        case '%':
            emit(tokens,
                 match('=') ? Token{TokenType::PERCENT_EQUAL, "%=", line} : Token{TokenType::PERCENT, "%", line});
            break;
        case '>':
            if (match('='))
                emit(tokens, {TokenType::GREATER_EQUAL, ">=", line});
            else
                emit(tokens, match('>') ? Token{TokenType::RSHIFT, ">>", line} : Token{TokenType::GREATER, ">", line});
            break;
        case '<':
            if (match('='))
                emit(tokens, {TokenType::LESS_EQUAL, "<=", line});
            else if (match('>'))
                emit(tokens, {TokenType::NOT_EQUAL, "<>", line});
            else
                emit(tokens, match('<') ? Token{TokenType::LSHIFT, "<<", line} : Token{TokenType::LESS, "<", line});
            break;
        case '&':
            emit(tokens, {TokenType::AMP, "&", line});
            break;
        case '|':
            emit(tokens, {TokenType::PIPE, "|", line});
            break;
        case '^':
            emit(tokens, {TokenType::CARET, "^", line});
            break;
        case '~':
            emit(tokens, {TokenType::TILDE, "~", line});
            break;
        case '{':
            emit(tokens, {TokenType::LBRACE, "{", line});
            break;
        case '}':
            emit(tokens, {TokenType::RBRACE, "}", line});
            break;
        case '[':
            emit(tokens, {TokenType::LBRACKET, "[", line});
            break;
        case ']':
            emit(tokens, {TokenType::RBRACKET, "]", line});
            break;
        case ':':
            emit(tokens, {TokenType::COLON, ":", line});
            break;
        case '?':
            emit(tokens, {TokenType::QUESTION, "?", line});
            break;
        case '"':
            interp_string(tokens);
            break;
        case '#':
            if (!match('#'))
                emit(tokens, {TokenType::HASH, "#", line});
            else
                emit(tokens, match('#') ? block_comment() : comment());
            break;
        default:
            if (is_dec(c)) {
                emit(tokens, number(false));
                break;
            }
            if (is_alpha(c) || c == '_') {
                emit(tokens, identifier());
                break;
            }
            // A whole codepoint, not one byte: a stray accented character (an editor's
            // non-breaking space, say) would otherwise be reported as half a character.
            fail("unexpected character '" + src.substr(pos - 1, utf8_step(src, (size_t)(pos - 1))) + "'", line);
        }
    }
    emit(tokens, {TokenType::EOF_T, "", line});
    return tokens;
}
