#include "lexer.h"
#include <stdexcept>

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

Token Lexer::identifier() {
    int start = pos - 1;
    while (!atEnd() && (std::isalnum(peek()) || peek() == '_'))
        advance();
    std::string lex = src.substr(start, pos - start);
    TokenType type = (lex == "var") ? TokenType::VAR : TokenType::IDENTIFIER;
    return {type, lex, line};
}

std::vector<Token> Lexer::tokenize() {
    std::vector<Token> tokens;
    while (!atEnd()) {
        skipWhitespace();
        if (atEnd()) break;

        char c = advance();
        switch (c) {
            case '\n': tokens.push_back({TokenType::NEWLINE, "\\n", line++}); break;
            case '=':  tokens.push_back({TokenType::EQUALS,  "=",   line});   break;
            case ',':  tokens.push_back({TokenType::COMMA,   ",",   line});   break;
            case '(':  tokens.push_back({TokenType::LPAREN,  "(",   line});   break;
            case ')':  tokens.push_back({TokenType::RPAREN,  ")",   line});   break;
            case '+':  tokens.push_back({TokenType::PLUS,    "+",   line});   break;
            case '-':  tokens.push_back({TokenType::MINUS,   "-",   line});   break;
            case '*':  tokens.push_back({TokenType::STAR,    "*",   line});   break;
            case '/':  tokens.push_back({TokenType::SLASH,   "/",   line});   break;
            case '%':
                while (!atEnd() && peek() != '\n') advance();
                break;
            default:
                if (std::isdigit(c)) { tokens.push_back(number()); break; }
                if (std::isalpha(c) || c == '_') { tokens.push_back(identifier()); break; }
                throw std::runtime_error(std::string("unexpected character: ") + c);
        }
    }
    tokens.push_back({TokenType::EOF_T, "", line});
    return tokens;
}
