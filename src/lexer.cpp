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
    {"enum", TokenType::ENUM},
};

Lexer::Lexer(std::string source, std::string filename, int file_idx)
    : src(std::move(source)), filename_(std::move(filename)), file_idx_(file_idx) {
}

char Lexer::peek() const {
    return at_end() ? '\0' : src[pos];
}
char Lexer::advance() {
    return src[pos++];
}
bool Lexer::at_end() const {
    return pos >= static_cast<int>(src.size());
}

void Lexer::skip_whitespace() {
    while (!at_end() && (peek() == ' ' || peek() == '\t' || peek() == '\r'))
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
    if (!leading_dot && src[start] == '0' && !at_end()) {
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
            while (!at_end()) {
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
            if (!at_end() && (std::isalnum((unsigned char)peek()) || peek() == '.'))
                invalid();
            return {TokenType::NUMBER, digits, line};
        }
    }

    // décimal : '_' uniquement entre deux chiffres, un seul '.', pas d'alnum/'.' collé
    bool last_was_digit = !leading_dot; // src[start] est un chiffre si !leading_dot
    bool prev_underscore = false;
    while (!at_end()) {
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
    if (!at_end() && (peek() == 'e' || peek() == 'E')) {
        if (prev_underscore) // '_' juste avant l'exposant → invalide (ex. 1_e5)
            throw std::runtime_error(filename_ + ":" + std::to_string(line) + ": invalid number literal");
        digits += 'e';
        advance();
        if (!at_end() && (peek() == '+' || peek() == '-')) {
            digits += peek();
            advance();
        }
        bool exp_digit = false;
        while (!at_end() && std::isdigit((unsigned char)peek())) {
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
    if (prev_underscore || (!at_end() && (std::isalnum((unsigned char)peek()) || peek() == '.' || peek() == '_')))
        throw std::runtime_error(filename_ + ":" + std::to_string(line) + ": invalid number literal");
    return {TokenType::NUMBER, digits, line};
}

Token Lexer::string() {
    int start = pos;
    while (!at_end() && peek() != '"' && peek() != '\n')
        advance();
    if (at_end() || peek() == '\n')
        throw std::runtime_error(filename_ + ":" + std::to_string(line) + ": unterminated string");
    std::string val = src.substr(start, pos - start);
    advance();
    return {TokenType::STRING, val, line};
}

// Emplacement POSITIONNEL vs expression à interpoler : positionnel si le préfixe
// (jusqu'au 1er ':') est vide ou uniquement des chiffres → {}, {0}, {1:.3f}, {:.3f}.
// Ces {…} sont laissés LITTÉRAUX dans la chaîne (remplis par printf). Toute autre
// forme ({x}, {a+b}, {x:.3f}) est une expression interpolée.
static bool is_positional_placeholder(const std::string& s) {
    size_t i = 0;
    while (i < s.size() && std::isspace((unsigned char)s[i])) i++;
    while (i < s.size() && std::isdigit((unsigned char)s[i])) i++;
    while (i < s.size() && std::isspace((unsigned char)s[i])) i++;
    return i == s.size() || s[i] == ':';
}

// Sépare une interpolation « expr:spec » sur le ':' de PREMIER NIVEAU (hors
// parenthèses/crochets/accolades et chaînes imbriquées) → préserve les map-littéraux
// {a:1}. Sans ':' de 1er niveau : spec vide, expr = tout le contenu.
static void split_interp_spec(const std::string& s, std::string& expr, std::string& spec) {
    int depth = 0;
    bool in_str = false;
    for (size_t i = 0; i < s.size(); ++i) {
        char c = s[i];
        if (in_str) {
            if (c == '"') in_str = false;
            continue;
        }
        if (c == '"') in_str = true;
        else if (c == '(' || c == '[' || c == '{') depth++;
        else if (c == ')' || c == ']' || c == '}') depth--;
        else if (c == ':' && depth == 0) {
            expr = s.substr(0, i);
            spec = s.substr(i + 1);
            return;
        }
    }
    expr = s;
    spec.clear();
}

void Lexer::interp_string(std::vector<Token>& out) {
    auto emit_tok = [&](Token t) { t.file_idx = file_idx_; out.push_back(std::move(t)); };

    int str_line = line;
    std::string literal;
    bool has_interp = false;

    while (!at_end() && peek() != '"' && peek() != '\n') {
        char c = advance();
        if (c == '\\' && !at_end() && peek() == '{') {
            literal += '{';
            advance();
        } else if (c == '{') {
            // Capturer le contenu {…} (accolades/strings imbriquées) SANS émettre,
            // pour décider : emplacement positionnel (littéral) vs expression interpolée.
            int depth = 1;
            int inner_start = pos;
            while (!at_end() && depth > 0) {
                char ec = peek();
                if (ec == '\n') break;
                if (ec == '"') {
                    advance();
                    while (!at_end() && peek() != '"' && peek() != '\n')
                        advance();
                    if (!at_end() && peek() == '"') advance();
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
            if (at_end() || peek() == '\n' || depth > 0)
                throw std::runtime_error(filename_ + ":" + std::to_string(str_line) + ": accolade non fermée dans l'interpolation");

            std::string inner = src.substr(inner_start, pos - inner_start);
            advance(); // consomme '}'

            // Positionnel ({}, {0}, {1:.3f}) → laissé littéral (rempli par printf).
            if (is_positional_placeholder(inner)) {
                literal += '{';
                literal += inner;
                literal += '}';
                continue;
            }

            // Expression interpolée, avec spec de format optionnel ({expr:spec}).
            std::string expr_src, spec;
            split_interp_spec(inner, expr_src, spec);

            emit_tok({has_interp ? TokenType::INTERP_MID : TokenType::INTERP_START, literal, str_line});
            has_interp = true;
            literal.clear();

            auto emit_sub = [&](const std::string& code) {
                Lexer sub(code, filename_, file_idx_);
                sub.line = str_line;
                for (auto& t : sub.tokenize())
                    if (t.type != TokenType::EOF_T)
                        emit_tok(t);
            };

            if (spec.empty()) {
                emit_sub(expr_src);
            } else {
                // Désucrage : {expr:spec} → __fmt(expr, "spec") (moteur de format partagé).
                emit_tok({TokenType::IDENTIFIER, "__fmt", str_line});
                emit_tok({TokenType::LPAREN, "(", str_line});
                emit_sub(expr_src);
                emit_tok({TokenType::COMMA, ",", str_line});
                emit_tok({TokenType::STRING, spec, str_line});
                emit_tok({TokenType::RPAREN, ")", str_line});
            }
        } else {
            literal += c;
        }
    }

    if (at_end() || peek() == '\n')
        throw std::runtime_error(filename_ + ":" + std::to_string(str_line) + ": unterminated string");
    advance(); // consomme '"'

    if (!has_interp)
        emit_tok({TokenType::STRING, literal, str_line});
    else
        emit_tok({TokenType::INTERP_END, literal, str_line});
}

Token Lexer::identifier() {
    int start = pos - 1;
    while (!at_end() && (std::isalnum((unsigned char)peek()) || peek() == '_'))
        advance();
    std::string lex = src.substr(start, pos - start);
    auto it = s_keywords.find(lex);
    return {it != s_keywords.end() ? it->second : TokenType::IDENTIFIER, lex, line};
}

Token Lexer::comment() {
    int start = pos;
    while (!at_end() && peek() != '\n')
        advance();
    return {TokenType::COMMENT, src.substr(start, pos - start), line};
}

Token Lexer::block_comment() {
    int start = pos;
    int hashes = 0;
    while (!at_end()) {
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

    while (!at_end()) {
        skip_whitespace();
        if (at_end())
            break;

        char c = advance();
        switch (c) {
        case '\n':
            line++;
            break;
        case '=':
            if (!at_end() && peek() == '=') {
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
            if (!at_end() && peek() == '.') {
                advance();
                if (!at_end() && peek() == '.') {
                    advance();
                    emit({TokenType::DOT_DOT_DOT, "...", line});
                } else
                    throw std::runtime_error("line " + std::to_string(line) +
                                             ": '..' is not valid syntax (use [a;b] for ranges)");
            } else if (!at_end() && std::isdigit((unsigned char)peek())) {
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
            if (!at_end() && peek() == '=') {
                advance();
                emit({TokenType::MINUS_EQUAL, "-=", line});
            } else
                emit({TokenType::MINUS, "-", line});
            break;
        case '*':
            if (!at_end() && peek() == '=') {
                advance();
                emit({TokenType::STAR_EQUAL, "*=", line});
            } else if (!at_end() && peek() == '*')
                throw std::runtime_error("line " + std::to_string(line) +
                                         ": '**' n'existe plus — utilisez '^' pour la puissance");
            else
                emit({TokenType::STAR, "*", line});
            break;
        case '/':
            if (!at_end() && peek() == '=') {
                advance();
                emit({TokenType::SLASH_EQUAL, "/=", line});
            } else if (!at_end() && peek() == '/') {
                advance();
                emit({TokenType::SLASH_SLASH, "//", line});
            } else
                emit({TokenType::SLASH, "/", line});
            break;
        case '%':
            if (!at_end() && peek() == '=') {
                advance();
                emit({TokenType::PERCENT_EQUAL, "%=", line});
            } else
                emit({TokenType::PERCENT, "%", line});
            break;
        case '>':
            if (!at_end() && peek() == '=') {
                advance();
                emit({TokenType::GREATER_EQUAL, ">=", line});
            } else if (!at_end() && peek() == '>') {
                advance();
                emit({TokenType::RSHIFT, ">>", line});
            } else
                emit({TokenType::GREATER, ">", line});
            break;
        case '<':
            if (!at_end() && peek() == '=') {
                advance();
                emit({TokenType::LESS_EQUAL, "<=", line});
            } else if (!at_end() && peek() == '>') {
                advance();
                emit({TokenType::NOT_EQUAL, "<>", line});
            } else if (!at_end() && peek() == '<') {
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
            interp_string(tokens);
            break;
        case '+':
            if (!at_end() && peek() == '=') {
                advance();
                emit({TokenType::PLUS_EQUAL, "+=", line});
            } else
                emit({TokenType::PLUS, "+", line});
            break;
        case '#':
            if (!at_end() && peek() == '#') {
                advance();
                if (!at_end() && peek() == '#') {
                    advance();
                    emit(block_comment());
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
