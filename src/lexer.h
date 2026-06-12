#pragma once
#include "token.h"
#include <string>
#include <vector>

class Lexer {
public:
    explicit Lexer(std::string source);
    std::vector<Token> tokenize();

private:
    std::string src;
    int pos = 0;
    int line = 1;

    char peek() const;
    char advance();
    bool atEnd() const;
    void skipWhitespace();
    Token number(bool leading_dot = false);
    Token string();
    Token identifier();
    Token comment();
    Token blockComment();
};
