#include "lexer.h"
#include <stdexcept>
#include <unordered_map>

static const std::unordered_map<std::string, TokenType> s_keywords = {
    {"var",      TokenType::VAR},
    {"global",   TokenType::GLOBAL},
    {"const",    TokenType::CONSTANT},
    {"while", TokenType::WHILE},
    {"do",    TokenType::DO},
    {"if",    TokenType::IF},
    {"then",  TokenType::THEN},
    {"end",   TokenType::END},
    {"break",    TokenType::BREAK},
    {"continue", TokenType::CONTINUE},
    {"true",  TokenType::TRUE},
    {"false", TokenType::FALSE},
    {"try",   TokenType::TRY},
    {"catch", TokenType::CATCH},
    {"throw",  TokenType::THROW},
    {"else",   TokenType::ELSE},
    {"elseif", TokenType::ELSEIF},
    {"func",   TokenType::FUNC},
    {"return", TokenType::RETURN},
    {"nil",    TokenType::NIL},
    {"or",     TokenType::OR},
    {"and",    TokenType::AND},
    {"not",    TokenType::NOT},
    {"for",    TokenType::FOR},
    {"in",     TokenType::IN},
    {"import",  TokenType::IMPORT},
    {"as",      TokenType::AS},
    {"class",   TokenType::CLASS},
    {"extends", TokenType::EXTENDS},
    {"static",  TokenType::STATIC},
    {"switch",  TokenType::SWITCH},
    {"case",    TokenType::CASE},
};

Lexer::Lexer(std::string source) : src(std::move(source)) {}

char Lexer::peek() const { return atEnd() ? '\0' : src[pos]; }
char Lexer::advance()    { return src[pos++]; }
bool Lexer::atEnd() const { return pos >= static_cast<int>(src.size()); }

void Lexer::skipWhitespace() {
    while (!atEnd() && (peek() == ' ' || peek() == '\t' || peek() == '\r'))
        advance();
}

Token Lexer::number(bool leading_dot) {
    int start = pos - 1;
    std::string digits;
    bool dot_seen = leading_dot;
    if (leading_dot) digits += '.';
    else             digits += src[start];
    while (!atEnd()) {
        char c = peek();
        if (std::isdigit(c) || c == '_') {
            advance();
            if (c != '_') digits += c;
        } else if (c == '.' && !dot_seen) {
            advance();
            dot_seen = true;
            digits += '.';
        } else {
            break;
        }
    }
    return {TokenType::NUMBER, digits, line};
}

Token Lexer::string() {
    int start = pos;
    while (!atEnd() && peek() != '"' && peek() != '\n')
        advance();
    if (atEnd() || peek() == '\n')
        throw std::runtime_error("line " + std::to_string(line) + ": unterminated string");
    std::string val = src.substr(start, pos - start);
    advance();
    return {TokenType::STRING, val, line};
}

Token Lexer::identifier() {
    int start = pos - 1;
    while (!atEnd() && (std::isalnum(peek()) || peek() == '_'))
        advance();
    std::string lex = src.substr(start, pos - start);
    auto it = s_keywords.find(lex);
    return {it != s_keywords.end() ? it->second : TokenType::IDENTIFIER, lex, line};
}

Token Lexer::comment() {
    int start = pos;
    while (!atEnd() && peek() != '\n') advance();
    return {TokenType::COMMENT, src.substr(start, pos - start), line};
}

Token Lexer::blockComment() {
    int start = pos;
    int hashes = 0;
    while (!atEnd()) {
        char c = advance();
        if (c == '\n') line++;
        hashes = (c == '#') ? hashes + 1 : 0;
        if (hashes == 3) break;
    }
    if (hashes < 3) throw std::runtime_error("line " + std::to_string(line) + ": unterminated block comment");
    return {TokenType::COMMENT, src.substr(start, pos - start - 3), line};
}

std::vector<Token> Lexer::tokenize() {
    std::vector<Token> tokens;
    int  paren_depth = 0;

    auto emit = [&](Token t) {
        tokens.push_back(std::move(t));
    };

    while (!atEnd()) {
        skipWhitespace();
        if (atEnd()) break;

        char c = advance();
        switch (c) {
            case '\n':
                line++;
                break;
            case '=':
                if (!atEnd() && peek() == '=') { advance(); emit({TokenType::EQUAL_EQUAL, "==", line}); }
                else emit({TokenType::EQUALS, "=", line});
                break;
            case ',':  emit({TokenType::COMMA,  ",", line}); break;
            case '(':  ++paren_depth; emit({TokenType::LPAREN,  "(", line}); break;
            case ')':  --paren_depth; emit({TokenType::RPAREN,  ")", line}); break;
            case '.':
                if (!atEnd() && peek() == '.') {
                    advance();
                    if (!atEnd() && peek() == '.') { advance(); emit({TokenType::DOT_DOT_DOT, "...", line}); }
                    else throw std::runtime_error("line " + std::to_string(line) + ": '..' is not valid syntax (use [a;b] for ranges)");
                } else if (!atEnd() && std::isdigit(peek())) {
                    emit(number(true)); // .5 → nombre à virgule
                } else {
                    emit({TokenType::DOT, ".", line});
                }
                break;
            case ';':
                if (paren_depth > 0) emit({TokenType::SEMICOLON, ";", line});
                else throw std::runtime_error("line " + std::to_string(line) + ": ';' is not valid syntax — statements are terminated by newlines");
                break;
            case '-':
                if (!atEnd() && peek() == '=') { advance(); emit({TokenType::MINUS_EQUAL, "-=", line}); }
                else emit({TokenType::MINUS, "-", line});
                break;
            case '*':
                if (!atEnd() && peek() == '=') { advance(); emit({TokenType::STAR_EQUAL, "*=", line}); }
                else if (!atEnd() && peek() == '*') { advance(); emit({TokenType::STAR_STAR, "**", line}); }
                else emit({TokenType::STAR, "*", line});
                break;
            case '/':
                if (!atEnd() && peek() == '=') { advance(); emit({TokenType::SLASH_EQUAL, "/=", line}); }
                else if (!atEnd() && peek() == '/') { advance(); emit({TokenType::SLASH_SLASH, "//", line}); }
                else emit({TokenType::SLASH, "/", line});
                break;
            case '%':
                if (!atEnd() && peek() == '=') { advance(); emit({TokenType::PERCENT_EQUAL, "%=", line}); }
                else emit({TokenType::PERCENT, "%", line});
                break;
            case '>':
                if (!atEnd() && peek() == '=') { advance(); emit({TokenType::GREATER_EQUAL, ">=", line}); }
                else if (!atEnd() && peek() == '>') { advance(); emit({TokenType::RSHIFT, ">>", line}); }
                else emit({TokenType::GREATER, ">", line});
                break;
            case '<':
                if (!atEnd() && peek() == '=') { advance(); emit({TokenType::LESS_EQUAL, "<=", line}); }
                else if (!atEnd() && peek() == '>') { advance(); emit({TokenType::NOT_EQUAL, "<>", line}); }
                else if (!atEnd() && peek() == '<') { advance(); emit({TokenType::LSHIFT, "<<", line}); }
                else emit({TokenType::LESS, "<", line});
                break;
            case '&':  emit({TokenType::AMP,   "&", line}); break;
            case '|':  emit({TokenType::PIPE,  "|", line}); break;
            case '^':  emit({TokenType::CARET, "^", line}); break;
            case '~':  emit({TokenType::TILDE, "~", line}); break;
            case '{':  ++paren_depth; emit({TokenType::LBRACE,   "{", line}); break;
            case '}':  --paren_depth; emit({TokenType::RBRACE,   "}", line}); break;
            case '[':  ++paren_depth; emit({TokenType::LBRACKET, "[", line}); break;
            case ']':  --paren_depth; emit({TokenType::RBRACKET, "]", line}); break;
            case ':':  emit({TokenType::COLON, ":", line}); break;
            case '"':  emit(string()); break;
            case '+':
                if (!atEnd() && peek() == '=') { advance(); emit({TokenType::PLUS_EQUAL, "+=", line}); }
                else emit({TokenType::PLUS, "+", line});
                break;
            case '#':
                if (!atEnd() && peek() == '#') {
                    advance();
                    if (!atEnd() && peek() == '#') { advance(); emit(blockComment()); }
                    else emit(comment());
                } else {
                    throw std::runtime_error("line " + std::to_string(line) + ": unexpected character '" + c + "'");
                }
                break;
            default:
                if (std::isdigit(c)) { emit(number(false)); break; }
                if (std::isalpha(c) || c == '_') { emit(identifier()); break; }
                throw std::runtime_error("line " + std::to_string(line) + ": unexpected character '" + c + "'");
        }
    }
    tokens.push_back({TokenType::EOF_T, "", line});
    return tokens;
}
