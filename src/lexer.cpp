#include "lexer.h"
#include <stdexcept>
#include <unordered_map>

static const std::unordered_map<std::string, TokenType> s_keywords = {
    {"var", TokenType::VAR},         {"global", TokenType::GLOBAL},
    {"const", TokenType::CONSTANT},  {"while", TokenType::WHILE},
    {"do", TokenType::DO},           {"if", TokenType::IF},
    {"then", TokenType::THEN},       {"end", TokenType::END},
    {"break", TokenType::BREAK},     {"continue", TokenType::CONTINUE},
    {"true", TokenType::TRUE},       {"false", TokenType::FALSE},
    {"try", TokenType::TRY},         {"catch", TokenType::CATCH},
    {"throw", TokenType::THROW},     {"else", TokenType::ELSE},
    {"elseif", TokenType::ELSEIF},   {"func", TokenType::FUNC},
    {"return", TokenType::RETURN},   {"nil", TokenType::NIL},
    {"or", TokenType::OR},           {"and", TokenType::AND},
    {"not", TokenType::NOT},         {"for", TokenType::FOR},
    {"in", TokenType::IN},           {"import", TokenType::IMPORT},
    {"as", TokenType::AS},           {"class", TokenType::CLASS},
    {"extends", TokenType::EXTENDS}, {"static", TokenType::STATIC},
    {"switch", TokenType::SWITCH},   {"case", TokenType::CASE},
};

Lexer::Lexer(std::string source, std::string filename, int file_idx)
    : src(std::move(source)), filename_(std::move(filename)), file_idx_(file_idx) {
}

char Lexer::peek() const {
    return atEnd() ? '\0' : src[pos];
}
char Lexer::advance() {
    return src[pos++];
}
bool Lexer::atEnd() const {
    return pos >= static_cast<int>(src.size());
}

void Lexer::skipWhitespace() {
    while (!atEnd() && (peek() == ' ' || peek() == '\t' || peek() == '\r'))
        advance();
}

Token Lexer::number(bool leading_dot) {
    int start = pos - 1;
    std::string digits;
    bool dot_seen = leading_dot;
    if (leading_dot)
        digits += '.';
    else
        digits += src[start];

    // littéraux hexadécimaux (0x..), octaux (0o..) et binaires (0b..) — entiers
    // '_' autorisé uniquement entre deux chiffres (cf. grammar.ebnf)
    if (!leading_dot && src[start] == '0' && !atEnd()) {
        char p = peek();
        if (p == 'x' || p == 'X' || p == 'o' || p == 'O' || p == 'b' || p == 'B') {
            char pl = (char)std::tolower((unsigned char)p); // 'x', 'o' ou 'b'
            const char* kind = pl == 'x' ? "hexadecimal" : pl == 'o' ? "octal" : "binary";
            auto invalid = [&]() {
                throw std::runtime_error(filename_ + ":" + std::to_string(line) + ": invalid " + kind + " literal");
            };
            advance(); // consomme x/o/b
            digits += pl;
            auto is_base_digit = [&](char c) {
                if (pl == 'x')
                    return (bool)std::isxdigit((unsigned char)c);
                if (pl == 'o')
                    return c >= '0' && c <= '7';
                return c == '0' || c == '1'; // binaire
            };
            bool any = false, last_was_digit = false;
            while (!atEnd()) {
                char c = peek();
                if (c == '_') {
                    if (!last_was_digit)
                        break; // '_' en tête ou doublé → invalide
                    advance();
                    last_was_digit = false;
                    continue;
                }
                if (!is_base_digit(c))
                    break;
                advance();
                digits += c;
                any = true;
                last_was_digit = true;
            }
            // pas de chiffre, underscore final, ou caractère alphanumérique/'.' collé
            if (!any || !last_was_digit)
                invalid();
            if (!atEnd() && (std::isalnum((unsigned char)peek()) || peek() == '.'))
                invalid();
            return {TokenType::NUMBER, digits, line};
        }
    }

    // décimal : '_' uniquement entre deux chiffres, un seul '.', pas d'alnum/'.' collé
    bool last_was_digit = !leading_dot; // src[start] est un chiffre si !leading_dot
    bool prev_underscore = false;
    while (!atEnd()) {
        char c = peek();
        if (std::isdigit((unsigned char)c)) {
            advance();
            digits += c;
            last_was_digit = true;
            prev_underscore = false;
        } else if (c == '_' && last_was_digit) {
            advance();
            last_was_digit = false;
            prev_underscore = true; // doit être suivi d'un chiffre
        } else if (c == '.' && !dot_seen && !prev_underscore) {
            advance();
            dot_seen = true;
            digits += '.';
            last_was_digit = false;
        } else {
            break;
        }
    }
    // exposant scientifique optionnel : [eE] [+-]? chiffres → le nombre est flottant.
    // (les littéraux hex/oct/bin sont déjà retournés plus haut, jamais ici.)
    if (!atEnd() && (peek() == 'e' || peek() == 'E')) {
        if (prev_underscore) // '_' juste avant l'exposant → invalide (ex. 1_e5)
            throw std::runtime_error(filename_ + ":" + std::to_string(line) + ": invalid number literal");
        digits += 'e';
        advance();
        if (!atEnd() && (peek() == '+' || peek() == '-')) {
            digits += peek();
            advance();
        }
        bool exp_digit = false;
        while (!atEnd() && std::isdigit((unsigned char)peek())) {
            digits += peek();
            advance();
            exp_digit = true;
        }
        if (!exp_digit) // 'e' sans chiffre (ex. 1e, 1e+)
            throw std::runtime_error(filename_ + ":" + std::to_string(line) + ": invalid number literal");
        last_was_digit = true;
        prev_underscore = false;
    }
    // '_' final (ou non suivi d'un chiffre), ou caractère alphanumérique / '.' / '_' collé
    if (prev_underscore || (!atEnd() && (std::isalnum((unsigned char)peek()) || peek() == '.' || peek() == '_')))
        throw std::runtime_error(filename_ + ":" + std::to_string(line) + ": invalid number literal");
    return {TokenType::NUMBER, digits, line};
}

Token Lexer::string() {
    int start = pos;
    while (!atEnd() && peek() != '"' && peek() != '\n')
        advance();
    if (atEnd() || peek() == '\n')
        throw std::runtime_error(filename_ + ":" + std::to_string(line) + ": unterminated string");
    std::string val = src.substr(start, pos - start);
    advance();
    return {TokenType::STRING, val, line};
}

void Lexer::interpString(std::vector<Token>& out) {
    auto emit_tok = [&](Token t) { t.file_idx = file_idx_; out.push_back(std::move(t)); };

    int str_line = line;
    std::string literal;
    bool has_interp = false;

    while (!atEnd() && peek() != '"' && peek() != '\n') {
        char c = advance();
        if (c == '\\' && !atEnd() && peek() == '{') {
            literal += '{';
            advance();
        } else if (c == '{') {
            emit_tok({has_interp ? TokenType::INTERP_MID : TokenType::INTERP_START, literal, str_line});
            has_interp = true;
            literal.clear();

            int depth = 1;
            int expr_start = pos;
            while (!atEnd() && depth > 0) {
                char ec = peek();
                if (ec == '\n') break;
                if (ec == '"') {
                    advance(); // consomme le '"' ouvrant
                    while (!atEnd() && peek() != '"' && peek() != '\n')
                        advance();
                    if (!atEnd() && peek() == '"') advance(); // consomme le '"' fermant
                } else if (ec == '{') {
                    depth++;
                    advance();
                } else if (ec == '}') {
                    depth--;
                    if (depth == 0) break;
                    advance();
                } else {
                    advance();
                }
            }
            if (atEnd() || peek() == '\n' || depth > 0)
                throw std::runtime_error(filename_ + ":" + std::to_string(str_line) + ": accolade non fermée dans l'interpolation");

            std::string expr_src = src.substr(expr_start, pos - expr_start);
            advance(); // consomme '}'

            if (expr_src.empty())
                throw std::runtime_error(filename_ + ":" + std::to_string(str_line) + ": interpolation vide {}");

            Lexer sub(expr_src, filename_, file_idx_);
            sub.line = str_line;
            auto sub_tokens = sub.tokenize();
            for (auto& t : sub_tokens)
                if (t.type != TokenType::EOF_T)
                    emit_tok(t);
        } else {
            literal += c;
        }
    }

    if (atEnd() || peek() == '\n')
        throw std::runtime_error(filename_ + ":" + std::to_string(str_line) + ": unterminated string");
    advance(); // consomme '"'

    if (!has_interp)
        emit_tok({TokenType::STRING, literal, str_line});
    else
        emit_tok({TokenType::INTERP_END, literal, str_line});
}

Token Lexer::identifier() {
    int start = pos - 1;
    while (!atEnd() && (std::isalnum((unsigned char)peek()) || peek() == '_'))
        advance();
    std::string lex = src.substr(start, pos - start);
    auto it = s_keywords.find(lex);
    return {it != s_keywords.end() ? it->second : TokenType::IDENTIFIER, lex, line};
}

Token Lexer::comment() {
    int start = pos;
    while (!atEnd() && peek() != '\n')
        advance();
    return {TokenType::COMMENT, src.substr(start, pos - start), line};
}

Token Lexer::blockComment() {
    int start = pos;
    int hashes = 0;
    while (!atEnd()) {
        char c = advance();
        if (c == '\n')
            line++;
        hashes = (c == '#') ? hashes + 1 : 0;
        if (hashes == 3)
            break;
    }
    if (hashes < 3)
        throw std::runtime_error(filename_ + ":" + std::to_string(line) + ": unterminated block comment");
    return {TokenType::COMMENT, src.substr(start, pos - start - 3), line};
}

std::vector<Token> Lexer::tokenize() {
    std::vector<Token> tokens;

    auto emit = [&](Token t) {
        t.file_idx = file_idx_;
        tokens.push_back(std::move(t));
    };

    while (!atEnd()) {
        skipWhitespace();
        if (atEnd())
            break;

        char c = advance();
        switch (c) {
        case '\n':
            line++;
            break;
        case '=':
            if (!atEnd() && peek() == '=') {
                advance();
                emit({TokenType::EQUAL_EQUAL, "==", line});
            } else
                emit({TokenType::EQUALS, "=", line});
            break;
        case ',':
            emit({TokenType::COMMA, ",", line});
            break;
        case '(':
            emit({TokenType::LPAREN, "(", line});
            break;
        case ')':
            emit({TokenType::RPAREN, ")", line});
            break;
        case '.':
            if (!atEnd() && peek() == '.') {
                advance();
                if (!atEnd() && peek() == '.') {
                    advance();
                    emit({TokenType::DOT_DOT_DOT, "...", line});
                } else
                    throw std::runtime_error("line " + std::to_string(line) +
                                             ": '..' is not valid syntax (use [a;b] for ranges)");
            } else if (!atEnd() && std::isdigit((unsigned char)peek())) {
                emit(number(true)); // .5 → nombre à virgule
            } else {
                emit({TokenType::DOT, ".", line});
            }
            break;
        case ';':
            // Toujours émis : le séparateur de range [a;b] en a besoin (y compris
            // pour les ranges ouverts à gauche ]a;b] où le compteur de crochets ne
            // pouvait pas distinguer ouverture/fermeture). Un ';' hors range est
            // rejeté par le parser (message clair au niveau instruction).
            emit({TokenType::SEMICOLON, ";", line});
            break;
        case '-':
            if (!atEnd() && peek() == '=') {
                advance();
                emit({TokenType::MINUS_EQUAL, "-=", line});
            } else
                emit({TokenType::MINUS, "-", line});
            break;
        case '*':
            if (!atEnd() && peek() == '=') {
                advance();
                emit({TokenType::STAR_EQUAL, "*=", line});
            } else if (!atEnd() && peek() == '*')
                throw std::runtime_error("line " + std::to_string(line) +
                                         ": '**' n'existe plus — utilisez '^' pour la puissance");
            else
                emit({TokenType::STAR, "*", line});
            break;
        case '/':
            if (!atEnd() && peek() == '=') {
                advance();
                emit({TokenType::SLASH_EQUAL, "/=", line});
            } else if (!atEnd() && peek() == '/') {
                advance();
                emit({TokenType::SLASH_SLASH, "//", line});
            } else
                emit({TokenType::SLASH, "/", line});
            break;
        case '%':
            if (!atEnd() && peek() == '=') {
                advance();
                emit({TokenType::PERCENT_EQUAL, "%=", line});
            } else
                emit({TokenType::PERCENT, "%", line});
            break;
        case '>':
            if (!atEnd() && peek() == '=') {
                advance();
                emit({TokenType::GREATER_EQUAL, ">=", line});
            } else if (!atEnd() && peek() == '>') {
                advance();
                emit({TokenType::RSHIFT, ">>", line});
            } else
                emit({TokenType::GREATER, ">", line});
            break;
        case '<':
            if (!atEnd() && peek() == '=') {
                advance();
                emit({TokenType::LESS_EQUAL, "<=", line});
            } else if (!atEnd() && peek() == '>') {
                advance();
                emit({TokenType::NOT_EQUAL, "<>", line});
            } else if (!atEnd() && peek() == '<') {
                advance();
                emit({TokenType::LSHIFT, "<<", line});
            } else
                emit({TokenType::LESS, "<", line});
            break;
        case '&':
            emit({TokenType::AMP, "&", line});
            break;
        case '|':
            emit({TokenType::PIPE, "|", line});
            break;
        case '^':
            emit({TokenType::CARET, "^", line});
            break;
        case '~':
            emit({TokenType::TILDE, "~", line});
            break;
        case '{':
            emit({TokenType::LBRACE, "{", line});
            break;
        case '}':
            emit({TokenType::RBRACE, "}", line});
            break;
        case '[':
            emit({TokenType::LBRACKET, "[", line});
            break;
        case ']':
            emit({TokenType::RBRACKET, "]", line});
            break;
        case ':':
            emit({TokenType::COLON, ":", line});
            break;
        case '?':
            emit({TokenType::QUESTION, "?", line});
            break;
        case '"':
            interpString(tokens);
            break;
        case '+':
            if (!atEnd() && peek() == '=') {
                advance();
                emit({TokenType::PLUS_EQUAL, "+=", line});
            } else
                emit({TokenType::PLUS, "+", line});
            break;
        case '#':
            if (!atEnd() && peek() == '#') {
                advance();
                if (!atEnd() && peek() == '#') {
                    advance();
                    emit(blockComment());
                } else
                    emit(comment());
            } else {
                emit({TokenType::HASH, "#", line});
            }
            break;
        default:
            if (std::isdigit((unsigned char)c)) {
                emit(number(false));
                break;
            }
            if (std::isalpha((unsigned char)c) || c == '_') {
                emit(identifier());
                break;
            }
            throw std::runtime_error(filename_ + ":" + std::to_string(line) + ": unexpected character '" + c + "'");
        }
    }
    tokens.push_back({TokenType::EOF_T, "", line, file_idx_});
    return tokens;
}
