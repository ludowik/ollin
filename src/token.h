#pragma once
#include <string>

enum class TokenType {
    NUMBER, IDENTIFIER,
    VAR, WHILE, IF, END, BREAK, TRUE, FALSE,
    EQUALS, COMMA, LPAREN, RPAREN,
    PLUS, MINUS, STAR, SLASH,
    PLUS_EQUAL,
    GREATER, LESS,
    NEWLINE, EOF_T
};

struct Token {
    TokenType type;
    std::string lexeme;
    int line;
};
