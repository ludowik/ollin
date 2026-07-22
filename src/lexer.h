#pragma once
#include "token.h"
#include <string>
#include <vector>

class Lexer {
  public:
    explicit Lexer(std::string source, std::string filename = "", int file_idx = 0);
    std::vector<Token> tokenize();

  private:
    std::string src;
    std::string filename_;
    int file_idx_ = 0;
    int pos = 0;
    int line = 1;

    char peek() const;
    char advance();
    bool atEnd() const;
    void skipWhitespace();
    Token number(bool leading_dot = false);
    Token string();
    void interpString(std::vector<Token>& out);
    Token identifier();
    Token comment();
    Token blockComment();
};
