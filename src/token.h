#pragma once
#include <string>

enum class TokenType {
    NUMBER, STRING, IDENTIFIER,
    VAR, WHILE, IF, THEN, END, BREAK, TRUE, FALSE,
    TRY, CATCH, THROW, ELSE,
    EQUALS, COMMA, LPAREN, RPAREN,
    PLUS, MINUS, STAR, SLASH,
    PLUS_EQUAL,
    GREATER, LESS,
    COMMENT,
    NEWLINE, EOF_T
};

struct Token {
    TokenType type;
    std::string lexeme;
    int line;
};
