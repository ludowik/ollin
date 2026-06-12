#include "lexer.h"
#include <stdexcept>
#include <unordered_map>

static const std::unordered_map<std::string, TokenType> s_keywords = {
    {"var",   TokenType::VAR},
    {"while", TokenType::WHILE},
    {"if",    TokenType::IF},
    {"then",  TokenType::THEN},
    {"end",   TokenType::END},
    {"break", TokenType::BREAK},
    {"true",  TokenType::TRUE},
    {"false", TokenType::FALSE},
    {"try",   TokenType::TRY},
    {"catch", TokenType::CATCH},
    {"throw", TokenType::THROW},
    {"else",  TokenType::ELSE},
};

Lexer::Lexer(std::string source) : src(std::move(source)) {}

char Lexer::peek() const { return atEnd() ? '\0' : src[pos]; }
char Lexer::advance()    { return src[pos++]; }
bool Lexer::atEnd() const { return pos >= static_cast<int>(src.size()); }

void Lexer::skipWhitespace() {
    while (!atEnd() && (peek() == ' ' || peek() == '\t' || peek() == '\r'))
        advance();
}

Token Lexer::number() {
    int start = pos - 1;
    while (!atEnd() && (std::isdigit(peek()) || peek() == '.'))
        advance();
    return {TokenType::NUMBER, src.substr(start, pos - start), line};
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
    while (!atEnd()) {
        skipWhitespace();
        if (atEnd()) break;

        char c = advance();
        switch (c) {
            case '\n': tokens.push_back({TokenType::NEWLINE,     "\\n", line++}); break;
            case '=':
                if (!atEnd() && peek() == '=') { advance(); tokens.push_back({TokenType::EQUAL_EQUAL, "==", line}); }
                else tokens.push_back({TokenType::EQUALS, "=", line});
                break;
            case ',':  tokens.push_back({TokenType::COMMA,       ",",   line});   break;
            case '(':  tokens.push_back({TokenType::LPAREN,      "(",   line});   break;
            case ')':  tokens.push_back({TokenType::RPAREN,      ")",   line});   break;
            case '-':  tokens.push_back({TokenType::MINUS,       "-",   line});   break;
            case '*':  tokens.push_back({TokenType::STAR,        "*",   line});   break;
            case '/':  tokens.push_back({TokenType::SLASH,       "/",   line});   break;
            case '>':  tokens.push_back({TokenType::GREATER,     ">",   line});   break;
            case '<':  tokens.push_back({TokenType::LESS,        "<",   line});   break;
            case '"':  tokens.push_back(string());                                break;
            case '+':
                if (!atEnd() && peek() == '=') { advance(); tokens.push_back({TokenType::PLUS_EQUAL, "+=", line}); }
                else tokens.push_back({TokenType::PLUS, "+", line});
                break;
            case '#':
                if (!atEnd() && peek() == '#') {
                    advance(); // 2e #
                    if (!atEnd() && peek() == '#') { advance(); tokens.push_back(blockComment()); }
                    else tokens.push_back(comment());
                } else {
                    throw std::runtime_error("line " + std::to_string(line) + ": unexpected character '" + c + "'");
                }
                break;
            default:
                if (std::isdigit(c)) { tokens.push_back(number());     break; }
                if (std::isalpha(c) || c == '_') { tokens.push_back(identifier()); break; }
                throw std::runtime_error("line " + std::to_string(line) + ": unexpected character '" + c + "'");
        }
    }
    tokens.push_back({TokenType::EOF_T, "", line});
    return tokens;
}
