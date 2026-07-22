#pragma once
#include "source_loc.h"
#include <string>

enum class TokenType {
    NUMBER,
    STRING,
    IDENTIFIER,
    VAR,
    GLOBAL,
    CONSTANT,
    WHILE,
    DO,
    IF,
    THEN,
    END,
    BREAK,
    CONTINUE,
    TRUE,
    FALSE,
    NOT,
    TRY,
    CATCH,
    THROW,
    ELSE,
    ELSEIF,
    FUNC,
    RETURN,
    NIL,
    FOR,
    IN,
    IMPORT,
    AS,
    CLASS,
    EXTENDS,
    STATIC,
    SWITCH,
    CASE,
    SEMICOLON,
    DOT_DOT_DOT,
    EQUALS,
    EQUAL_EQUAL,
    COMMA,
    LPAREN,
    RPAREN,
    PLUS,
    MINUS,
    STAR,
    SLASH,
    PERCENT,
    SLASH_SLASH,
    PLUS_EQUAL,
    MINUS_EQUAL,
    STAR_EQUAL,
    SLASH_EQUAL,
    PERCENT_EQUAL,
    OR,
    AND,
    GREATER,
    LESS,
    GREATER_EQUAL,
    LESS_EQUAL,
    NOT_EQUAL,
    LBRACE,
    RBRACE,
    LBRACKET,
    RBRACKET,
    COLON,
    DOT,
    AMP,
    PIPE,
    CARET,
    TILDE,
    LSHIFT,
    RSHIFT,
    HASH,
    QUESTION,
    COMMENT,
    INTERP_START, // début d'une chaîne interpolée : texte avant le premier {
    INTERP_MID,   // texte entre deux segments interpolés
    INTERP_END,   // texte après le dernier segment interpolé
    EOF_T
};

struct Token {
    TokenType type;
    std::string lexeme;
    int line;
    int file_idx = 0;
    SourceLoc sloc() const { return {(uint16_t)file_idx, (uint16_t)line}; }
};
