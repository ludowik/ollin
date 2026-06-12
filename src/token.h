#pragma once
#include <string>

enum class TokenType {
    NUMBER, IDENTIFIER,
    VAR,
    EQUALS, COMMA, LPAREN, RPAREN,
    PLUS, MINUS, STAR, SLASH,
    NEWLINE, EOF_T
};

struct Token {
    TokenType type;
    std::string lexeme;
    int line;
};
