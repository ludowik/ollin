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
    int len_ = 0;
    int pos = 0;
    int line = 1;

    char peek() const;
    char advance();
    bool at_end() const;
    // Consumes the next character when it is c. peek() yields '\0' past the end, so no
    // end-of-source guard is needed at the call sites.
    bool match(char c);
    [[noreturn]] void fail(const std::string& msg, int at_line) const;
    void emit(std::vector<Token>& out, Token t) const;
    void skip_whitespace();
    Token number(bool leading_dot = false);
    void interp_string(std::vector<Token>& out);
    Token identifier();
    Token comment();
    Token block_comment();
};
