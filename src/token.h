#pragma once
#include <string>

enum class TokenType {
    NUMBER, STRING, IDENTIFIER,
    VAR, WHILE, IF, THEN, END, BREAK, TRUE, FALSE,
    TRY, CATCH, THROW, ELSE, FUNC, RETURN, NIL,
    DOT_DOT_DOT,
    EQUALS, EQUAL_EQUAL, COMMA, LPAREN, RPAREN,
    PLUS, MINUS, STAR, SLASH, PERCENT,
    PLUS_EQUAL, MINUS_EQUAL, STAR_EQUAL, SLASH_EQUAL, PERCENT_EQUAL,
    OR, AND,
    GREATER, LESS,
    COMMENT,
    NEWLINE, EOF_T
};

struct Token {
    TokenType type;
    std::string lexeme;
    int line;
};
