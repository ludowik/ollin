#include "compiler.h"
#include "modules/modules.h"
#include <algorithm>
#include <stdexcept>
#include <unordered_set>

// ── upvalue resolution ────────────────────────────────────────────────────────

int Compiler::resolveUpvalue(const std::string& name) {
    auto it = cur_upval_idx_.find(name);
    if (it != cur_upval_idx_.end())
        return it->second;
    if (outer_scopes_.empty())
        return -1;
    return resolveUpvalFrom((int)outer_scopes_.size() - 1, name);
}

int Compiler::resolveUpvalFrom(int scope_idx, const std::string& name) {
    OuterScope& scope = outer_scopes_[scope_idx];
    auto local_it = scope.regs.find(name);
    if (local_it != scope.regs.end())
        return captureUpvalChain(scope_idx, true, (uint8_t)local_it->second, name);
    auto uv_it = scope.upval_idx.find(name);
    if (uv_it != scope.upval_idx.end())
        return captureUpvalChain(scope_idx, false, (uint8_t)uv_it->second, name);
    if (scope_idx == 0)
        return -1;
    int outer_uv = resolveUpvalFrom(scope_idx - 1, name);
    if (outer_uv < 0)
        return -1;
    return captureUpvalChain(scope_idx, false, (uint8_t)outer_uv, name);
}

int Compiler::captureUpvalChain(int scope_idx, bool is_local, uint8_t idx, const std::string& name) {
    bool cur_is_local = is_local;
    uint8_t cur_idx = idx;

    // Propagate through intermediate function scopes
    for (int i = scope_idx + 1; i < (int)outer_scopes_.size(); i++) {
        OuterScope& s = outer_scopes_[i];
        auto it = s.upval_idx.find(name);
        if (it != s.upval_idx.end()) {
            cur_idx = (uint8_t)it->second;
            cur_is_local = false;
        } else if (s.func_proto_idx >= 0) {
            int uv_i = (int)chunk.funcs[s.func_proto_idx].upvals.size();
            if (uv_i > 255) // l'index d'upvalue est un opérande 8 bits
                throw std::runtime_error("function captures more than 255 upvalues");
            chunk.funcs[s.func_proto_idx].upvals.push_back({cur_is_local, cur_idx});
            s.upval_idx[name] = uv_i;
            cur_idx = (uint8_t)uv_i;
            cur_is_local = false;
        }
    }

    // Add to current function
    {
        auto it = cur_upval_idx_.find(name);
        if (it != cur_upval_idx_.end())
            return it->second;
    }
    if (current_func_idx_ < 0)
        return -1; // in main chunk, no FuncProto
    int uv_i = (int)chunk.funcs[current_func_idx_].upvals.size();
    if (uv_i > 255) // l'index d'upvalue est un opérande 8 bits
        throw std::runtime_error("function captures more than 255 upvalues");
    chunk.funcs[current_func_idx_].upvals.push_back({cur_is_local, cur_idx});
    cur_upval_idx_[name] = uv_i;
    return uv_i;
}

// ── constant evaluator (for default parameter values) ─────────────────────────
static Value evalConstant(const Expr& e) {
    if (auto* n = dynamic_cast<const NumberExpr*>(&e))
        return n->is_integer ? Value(n->ival) : numValue(n->value);
    if (auto* s = dynamic_cast<const StringExpr*>(&e))
        return Value(s->value);
    if (auto* b = dynamic_cast<const BoolExpr*>(&e))
        return Value((int64_t)(b->value ? 1 : 0));
    if (dynamic_cast<const NilExpr*>(&e))
        return Value{};
    throw std::runtime_error("default values must be literal constants (not a runtime expression)");
}

// ── arithmetic op helpers ─────────────────────────────────────────────────────
static Op charToOp(char op) {
    switch (op) {
    case '+':
        return Op::ADD;
    case '-':
        return Op::SUB;
    case '*':
        return Op::MUL;
    case '/':
        return Op::DIV;
    case '%':
        return Op::MOD;
    default:
        throw std::runtime_error(std::string("unknown assign op: ") + op);
    }
}
static Op tokenToOp(TokenType op) {
    switch (op) {
    case TokenType::PLUS_EQUAL:
        return Op::ADD;
    case TokenType::MINUS_EQUAL:
        return Op::SUB;
    case TokenType::STAR_EQUAL:
        return Op::MUL;
    case TokenType::SLASH_EQUAL:
        return Op::DIV;
    case TokenType::PERCENT_EQUAL:
        return Op::MOD;
    default:
        throw std::runtime_error("unknown compound index assign op");
    }
}

// Opcode d'un opérateur binaire NON court-circuit (arith / comparaison / bitwise).
// '&' et '|' (and/or) sont exclus : ils compilent en court-circuit (JUMP_IF_FALSE),
// jamais via cet opcode. Partagé par visit(BinaryExpr) et compileInto → évite de
// dupliquer le switch (et supprime les anciens cas '&'/'|' morts).
static Op binaryArithOpcode(char op) {
    switch (op) {
    case '+':
        return Op::ADD;
    case '-':
        return Op::SUB;
    case '*':
        return Op::MUL;
    case '/':
        return Op::DIV;
    case 'q':
        return Op::IDIV;
    case 'p':
        return Op::POW;
    case '%':
        return Op::MOD;
    case '>':
        return Op::GT;
    case '<':
        return Op::LT;
    case 'G':
        return Op::GE;
    case 'L':
        return Op::LE;
    case 'N':
        return Op::NEQ;
    case '=':
        return Op::EQ;
    case 'o':
        return Op::BOR;
    case 'b':
        return Op::BAND;
    case 'x':
        return Op::BXOR;
    case 'l':
        return Op::BLSHIFT;
    case 'r':
        return Op::BRSHIFT;
    default:
        throw std::runtime_error(std::string("unknown binary op: ") + op);
    }
}

static Op unaryOpcode(char op) {
    switch (op) {
    case '-':
        return Op::NEGATE;
    case '!':
        return Op::NOT;
    case '~':
        return Op::BNOT;
    default:
        throw std::runtime_error(std::string("unknown unary op: ") + op);
    }
}

// Épilogue void implicite d'une fonction/méthode. Omis si le corps se termine déjà
// par un RETURN/RETURN_V : la dernière instruction retourne inconditionnellement,
// donc un RETURN de plus serait inatteignable (code mort). Ne concerne PAS le
// `return` explicite sans valeur, qui doit toujours être émis.
static void emitImplicitReturn(Chunk& chunk) {
    if (!chunk.code.empty()) {
        Op last = (Op)iOP(chunk.code.back());
        if (last == Op::RETURN || last == Op::RETURN_V)
            return;
    }
    chunk.emit(makeABC((uint8_t)Op::RETURN, 0, 0, 0));
}

// ── pre-scan locals in a block (for register pre-allocation) ─────────────────
// collect_funcs=true inside function bodies (nested FuncDecls need a local register)
// collect_funcs=false at top level (top-level funcs are accessed via func_table)
// ── pre-scan local declarations ───────────────────────────────────────────────
struct CollectLocalsVisitor : StmtQuery {
    std::vector<std::string>& out;
    std::unordered_set<std::string>& seen;
    bool collect_funcs;

    CollectLocalsVisitor(std::vector<std::string>& out, std::unordered_set<std::string>& seen,
                         bool collect_funcs)
        : out(out), seen(seen), collect_funcs(collect_funcs) {}

    void visit(const VarDeclStmt& s) override {
        if (!s.is_global) { // 'global' → table des globaux, pas de registre
                            // 'constant' → locale normale (immuable à la compilation)
            for (auto& n : s.names) {
                if (!seen.insert(n).second) {
                    throw std::runtime_error("local variable '" + n + "' already declared in this scope");
                }
                out.push_back(n);
            }
        }
    }
    void visit(const FuncDeclStmt& s) override {
        // Ne pas descendre dans le corps : les locales d'une fonction sont dans sa propre portée.
        if (collect_funcs && seen.insert(s.name).second) {
            out.push_back(s.name);
        }
    }
    void visit(const ForIterStmt& s) override {
        // var1/var2 ne sont PAS des locales permanentes (scopées à la boucle).
        run(s.body);
    }
    void visit(const WhileStmt& s) override {
        run(s.body);
    }
    void visit(const IfStmt& s) override {
        run(s.then_body);
        for (auto& ei : s.else_ifs)
            run(ei.body);
        run(s.else_body);
    }
    void visit(const TryCatchStmt& s) override {
        run(s.try_body);
        if (!s.catch_var.empty() && seen.insert(s.catch_var).second) {
            out.push_back(s.catch_var);
        }
        run(s.catch_body);
        run(s.else_body);
    }
    void visit(const BlockStmt& s) override {
        run(s.stmts);
    }
    void visit(const SwitchStmt& s) override {
        for (auto& arm : s.cases)
            run(arm.body);
        run(s.else_body);
    }
};

static void collectLocals(const std::vector<std::unique_ptr<Stmt>>& stmts, std::vector<std::string>& out,
                          bool collect_funcs = true) {
    std::unordered_set<std::string> seen(out.begin(), out.end());
    CollectLocalsVisitor v(out, seen, collect_funcs);
    v.run(stmts);
}

// ── pre-scan global declarations (program-wide, incl. nested in functions) ────
// Les globaux déclarés avec 'global' sont visibles partout, quel que soit
// l'endroit de leur déclaration → on les collecte tous avant la compilation.
struct CollectGlobalsVisitor : StmtQuery {
    std::unordered_set<std::string>& out;

    explicit CollectGlobalsVisitor(std::unordered_set<std::string>& out) : out(out) {}

    void visit(const VarDeclStmt& s) override {
        if (s.is_global) {
            for (auto& n : s.names) {
                if (!out.insert(n).second) {
                    throw std::runtime_error("global variable '" + n + "' already declared");
                }
            }
        }
    }
    void visit(const FuncDeclStmt& s) override {
        run(s.body);
    }
    void visit(const ForIterStmt& s) override {
        run(s.body);
    }
    void visit(const WhileStmt& s) override {
        run(s.body);
    }
    void visit(const IfStmt& s) override {
        run(s.then_body);
        for (auto& ei : s.else_ifs)
            run(ei.body);
        run(s.else_body);
    }
    void visit(const TryCatchStmt& s) override {
        run(s.try_body);
        run(s.catch_body);
        run(s.else_body);
    }
    void visit(const BlockStmt& s) override {
        run(s.stmts);
    }
    void visit(const ClassDeclStmt& s) override {
        out.insert(s.name); // classe visible par ses propres méthodes
        for (auto& m : s.methods)
            run(m->body);
    }
    void visit(const SwitchStmt& s) override {
        for (auto& arm : s.cases)
            run(arm.body);
        run(s.else_body);
    }
};

static void collectGlobals(const std::vector<std::unique_ptr<Stmt>>& stmts,
                           std::unordered_set<std::string>& out) {
    CollectGlobalsVisitor v(out);
    v.run(stmts);
}

// ── compile expression into a specific destination register ──────────────────
void Compiler::compileInto(const Expr& e, int dest) {
    if (auto* n = dynamic_cast<const NumberExpr*>(&e)) {
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)dest,
                           chunk.addConstant(n->is_integer ? Value(n->ival) : numValue(n->value))));
    } else if (auto* s = dynamic_cast<const StringExpr*>(&e)) {
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)dest, chunk.addConstant(Value(s->value))));
    } else if (auto* b = dynamic_cast<const BoolExpr*>(&e)) {
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)dest, chunk.addConstant(Value((int64_t)(b->value ? 1 : 0)))));
    } else if (dynamic_cast<const NilExpr*>(&e)) {
        chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)dest, 0, 0));
    } else if (auto* bin = dynamic_cast<const BinaryExpr*>(&e); bin && bin->op != '&' && bin->op != '|') {
        // Binaire non court-circuit : émettre l'op FINALE directement dans dest, sans
        // temporaire+MOVE. Sûr : une instruction 3-adresses lit rL/rR AVANT d'écrire
        // dest (aucun aliasing possible même si dest est aussi un opérande, ex.
        // a = a - b → SUB Ra,Ra,Rb). dest < reg_top_ chez tous les appelants, donc les
        // temporaires d'opérandes (alloués à reg_top_+) ne recouvrent jamais dest.
        int saved = reg_top_;
        bin->left->accept(*this);
        int rL = last_reg_;
        if (reg_top_ <= rL) // protège rL d'un appel 0-arg (cf. visit(BinaryExpr))
            reg_top_ = rL + 1;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        bin->right->accept(*this);
        int rR = last_reg_;
        chunk.emit(makeABC((uint8_t)binaryArithOpcode(bin->op), (uint8_t)dest, (uint8_t)rL, (uint8_t)rR));
        reg_top_ = saved;
        last_reg_ = dest;
    } else if (auto* un = dynamic_cast<const UnaryExpr*>(&e)) {
        // Unaire : op directement dans dest (même sûreté que ci-dessus, un seul opérande).
        int saved = reg_top_;
        un->operand->accept(*this);
        int rIn = last_reg_;
        chunk.emit(makeABC((uint8_t)unaryOpcode(un->op), (uint8_t)dest, (uint8_t)rIn, 0));
        reg_top_ = saved;
        last_reg_ = dest;
    } else {
        int saved = reg_top_;
        e.accept(*this);
        if (last_reg_ != dest)
            chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)dest, (uint8_t)last_reg_, 0));
        reg_top_ = saved;
    }
}

// ── top-level compile ─────────────────────────────────────────────────────────
Chunk Compiler::compile(const Program& prog) {
    reg_top_ = 0;
    reg_count_ = 8;
    collectGlobals(prog.stmts, declared_globals_);
    for (auto& n : builtinModuleNames())
        declared_globals_.insert(n);
    for (auto& n : builtinFuncNames())
        declared_globals_.insert(n);
    declared_globals_.insert("deltaTime");
    declared_globals_.insert("elapsedTime");
    declared_globals_.insert("W");   // largeur de la zone de rendu (défaut : window.width)
    declared_globals_.insert("H");   // hauteur de la zone de rendu (défaut : window.height)
    declared_globals_.insert("CW");  // centre X de la zone de rendu (W / 2)
    declared_globals_.insert("CH");  // centre Y de la zone de rendu (H / 2)
    // Pre-scan all top-level var/for declarations → registers (like Lua's local in main chunk)
    // collect_funcs=false: top-level functions are in func_table, not in local registers
    std::vector<std::string> top_locals;
    collectLocals(prog.stmts, top_locals, false);
    for (auto& name : top_locals)
        local_regs_[name] = reg_top_++;
    locals_top_ = reg_top_;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;

    for (auto& s : prog.stmts)
        s->accept(*this);
    // Même garde que pour les fonctions : les registres sont des opérandes 8 bits.
    // Sans elle, un script top-level > 255 registres tronquait silencieusement.
    if (reg_count_ > 255)
        throw std::runtime_error("top-level code uses more than 255 registers");
    chunk.top_reg_count = (uint8_t)std::max(reg_count_, 8);
    chunk.emit(makeBx((uint8_t)Op::HALT, 0));
    // Les cibles de saut sont des adresses absolues 16 bits (Bx). Au-delà de 65535
    // instructions, elles seraient tronquées → saut vers une mauvaise adresse.
    if (chunk.code.size() > 65535)
        throw std::runtime_error("program too large (> 65535 instructions)");
    return std::move(chunk);
}

// ── statements ────────────────────────────────────────────────────────────────

// Vrai si l'expression est un appel (toute forme) — utilisé pour la
// destructuration multi-retour, qui doit lire plusieurs valeurs à la base.
static bool isCallNode(const Expr* e) {
    return dynamic_cast<const CallExpr*>(e) || dynamic_cast<const ExprCallExpr*>(e) ||
           dynamic_cast<const MethodCallExpr*>(e);
}

void Compiler::visit(const VarDeclStmt& s) {
    noteLine(s.line);

    // Multi-retour : plusieurs cibles, une seule valeur qui est un APPEL (de
    // n'importe quelle forme : fonction nommée, closure, appel dynamique, méthode).
    // On compile l'appel à une base connue ; la VM y laisse toutes les valeurs de
    // retour (RETURN copie R[A..A+k-1] → base..base+k-1). On lit ensuite base+i.
    // (Généralise l'ancien chemin qui ne gérait que CALL_FUNC nommé → corrige le
    // crash sur closure et la perte de valeurs pour méthodes/appels dynamiques.)
    if (s.names.size() > 1 && s.values.size() == 1 && isCallNode(s.values[0].get())) {
        int base = reg_top_;
        s.values[0]->accept(*this); // laisse k valeurs de retour en base..base+k-1
        int n = (int)s.names.size();
        if (base + n > reg_count_)
            reg_count_ = base + n; // ces registres sont vivants (lus ci-dessous)
        // Met à nil les cibles au-delà de ce que l'appel a renvoyé (k < n) : sinon
        // elles liraient des registres périmés (ex. var a,b = len(x) → b doit être nil).
        chunk.emit(makeABC((uint8_t)Op::SPREAD_RESULTS, (uint8_t)base, (uint8_t)n, 0));
        for (int i = 0; i < n; ++i) {
            if (s.is_global) {
                chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)(base + i), chunk.addIdentifier(s.names[i])));
            } else {
                int dest = local_regs_.at(s.names[i]);
                if (base + i != dest)
                    chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)dest, (uint8_t)(base + i), 0));
            }
        }
        reg_top_ = base;
        return;
    }

    // 'global' declaration → store into the VM-wide globals table
    if (s.is_global) {
        // Normal: parallel assignment (or nil when no value)
        for (int i = 0; i < (int)s.names.size(); ++i) {
            int saved = reg_top_;
            int src = allocReg();
            if (i < (int)s.values.size()) {
                compileInto(*s.values[i], src);
            } else {
                chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)src, 0, 0));
            }
            chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)src, chunk.addIdentifier(s.names[i])));
            reg_top_ = saved;
        }
        return;
    }

    // Normal: compile each value into its pre-allocated local register
    for (int i = 0; i < (int)s.names.size(); ++i) {
        int dest = local_regs_.at(s.names[i]);
        if (i < (int)s.values.size()) {
            compileInto(*s.values[i], dest);
        } else {
            chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)dest, 0, 0));
        }
    }
    // Register constants so any later assignment is caught at compile time
    if (s.is_constant)
        for (auto& n : s.names)
            const_names_.insert(n);
}

void Compiler::visit(const WhileStmt& s) {
    noteLine(s.line);
    auto loop_start = (uint16_t)chunk.currentPos();
    int saved = reg_top_;
    s.cond->accept(*this);
    int cond_r = last_reg_;
    size_t exit_patch = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);
    reg_top_ = saved;

    break_patches.push_back({});
    continue_patches.push_back({});
    for (auto& stmt : s.body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }
    // continue → réévaluation de la condition
    for (size_t p : continue_patches.back())
        chunk.patchJump(p, loop_start);
    continue_patches.pop_back();
    chunk.emit(makeBx((uint8_t)Op::JUMP, loop_start));
    chunk.patchJump(exit_patch, (uint16_t)chunk.currentPos());
    for (size_t p : break_patches.back())
        chunk.patchJump(p, (uint16_t)chunk.currentPos());
    break_patches.pop_back();
}

void Compiler::visit(const IfStmt& s) {
    noteLine(s.line);
    std::vector<size_t> end_patches;

    int saved = reg_top_;
    s.cond->accept(*this);
    int cond_r = last_reg_;
    reg_top_ = saved;
    size_t next_patch = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);

    for (auto& stmt : s.then_body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }
    end_patches.push_back(chunk.emitJump(Op::JUMP));

    for (auto& ei : s.else_ifs) {
        chunk.patchJump(next_patch, (uint16_t)chunk.currentPos());
        int s2 = reg_top_;
        ei.cond->accept(*this);
        int er = last_reg_;
        reg_top_ = s2;
        next_patch = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)er);
        for (auto& stmt : ei.body) {
            int s3 = reg_top_;
            stmt->accept(*this);
            reg_top_ = s3;
        }
        end_patches.push_back(chunk.emitJump(Op::JUMP));
    }

    chunk.patchJump(next_patch, (uint16_t)chunk.currentPos());
    for (auto& stmt : s.else_body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }

    uint16_t end_addr = (uint16_t)chunk.currentPos();
    for (size_t p : end_patches)
        chunk.patchJump(p, end_addr);
}

void Compiler::visit(const SwitchStmt& s) {
    noteLine(s.line);

    int saved = reg_top_;
    s.subject->accept(*this);
    int subj_r = last_reg_;
    // Réserver le registre du sujet : un sujet appel 0-argument laisse
    // reg_top_ == subj_r, donc sans cette garde l'évaluation des valeurs de 'case'
    // réalloue et écrase le sujet (mauvaise branche prise). Ex. : switch f().
    if (reg_top_ <= subj_r)
        reg_top_ = subj_r + 1;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;
    int above_subj = reg_top_; // subj_r reste vivant pendant tous les bras

    std::vector<size_t> end_patches;
    break_patches.push_back({}); // break à l'intérieur du switch cible end_addr

    for (auto& arm : s.cases) {
        std::vector<size_t> body_patches;
        size_t next_arm_patch = 0;

        for (size_t vi = 0; vi < arm.values.size(); ++vi) {
            bool is_last = (vi == arm.values.size() - 1);
            reg_top_ = above_subj;
            arm.values[vi]->accept(*this);
            int val_r = last_reg_;
            int cond_r = allocReg(); // allocReg() met à jour reg_count_
            reg_top_ = above_subj;   // libère le temporaire après EQ
            chunk.emit(makeABC((uint8_t)Op::EQ, (uint8_t)cond_r, (uint8_t)subj_r, (uint8_t)val_r));
            if (!is_last) {
                size_t skip = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);
                body_patches.push_back(chunk.emitJump(Op::JUMP));
                chunk.patchJump(skip, (uint16_t)chunk.currentPos());
            } else {
                next_arm_patch = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)cond_r);
            }
        }

        uint16_t body_addr = (uint16_t)chunk.currentPos();
        for (size_t p : body_patches)
            chunk.patchJump(p, body_addr);

        reg_top_ = above_subj;
        for (auto& stmt : arm.body) {
            int st = reg_top_;
            stmt->accept(*this);
            reg_top_ = st;
        }
        end_patches.push_back(chunk.emitJump(Op::JUMP));
        chunk.patchJump(next_arm_patch, (uint16_t)chunk.currentPos());
    }

    reg_top_ = above_subj;
    for (auto& stmt : s.else_body) {
        int st = reg_top_;
        stmt->accept(*this);
        reg_top_ = st;
    }

    uint16_t end_addr = (uint16_t)chunk.currentPos();
    for (size_t p : end_patches)
        chunk.patchJump(p, end_addr);
    for (size_t p : break_patches.back())
        chunk.patchJump(p, end_addr);
    break_patches.pop_back();
    reg_top_ = saved;
}

void Compiler::visit(const BreakStmt& s) {
    if (break_patches.empty())
        throw std::runtime_error("line " + std::to_string(s.line) + ": break outside loop");
    break_patches.back().push_back(chunk.emitJump(Op::JUMP));
}

void Compiler::visit(const ContinueStmt& s) {
    if (continue_patches.empty())
        throw std::runtime_error("line " + std::to_string(s.line) + ": continue outside loop");
    continue_patches.back().push_back(chunk.emitJump(Op::JUMP));
}

void Compiler::visit(const AssignStmt& s) {
    noteLine(s.line);
    if (const_names_.count(s.name))
        throw std::runtime_error("line " + std::to_string(s.line > 0 ? s.line : current_line_) +
                                 ": cannot assign to const '" + s.name + "'");
    // Also block assignment when name is a constant captured from an outer scope
    for (auto& scope : outer_scopes_)
        if (scope.consts.count(s.name))
            throw std::runtime_error("line " + std::to_string(s.line > 0 ? s.line : current_line_) +
                                     ": cannot assign to const '" + s.name + "'");
    {
        auto it = local_regs_.find(s.name);
        if (it != local_regs_.end()) {
            int dest = it->second;
            if (s.op == '\0') {
                compileInto(*s.value, dest);
            } else {
                // Compound: rhs is fully evaluated before writing back to dest
                int saved = reg_top_;
                s.value->accept(*this);
                int rhs = last_reg_;
                // Emit op directly into dest — safe: rhs is already in a register
                chunk.emit(makeABC((uint8_t)charToOp(s.op), (uint8_t)dest, (uint8_t)dest, (uint8_t)rhs));
                reg_top_ = saved;
            }
            return;
        }
    }
    // Upvalue
    {
        int uv = resolveUpvalue(s.name);
        if (uv >= 0) {
            int saved = reg_top_;
            if (s.op == '\0') {
                s.value->accept(*this);
                chunk.emit(makeABC((uint8_t)Op::SET_UPVAL, (uint8_t)last_reg_, (uint8_t)uv, 0));
            } else {
                int cur = allocReg();
                chunk.emit(makeABC((uint8_t)Op::GET_UPVAL, (uint8_t)cur, (uint8_t)uv, 0));
                s.value->accept(*this);
                int rhs = last_reg_;
                int res = allocReg();
                if (reg_top_ > reg_count_)
                    reg_count_ = reg_top_;
                chunk.emit(makeABC((uint8_t)charToOp(s.op), (uint8_t)res, (uint8_t)cur, (uint8_t)rhs));
                chunk.emit(makeABC((uint8_t)Op::SET_UPVAL, (uint8_t)res, (uint8_t)uv, 0));
            }
            reg_top_ = saved;
            return;
        }
    }
    // Global variable (declared with 'global') → store into the globals table
    if (declared_globals_.count(s.name)) {
        int saved = reg_top_;
        if (s.op == '\0') {
            s.value->accept(*this);
            chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)last_reg_, chunk.addIdentifier(s.name)));
        } else {
            int cur = allocReg();
            chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)cur, chunk.addIdentifier(s.name)));
            s.value->accept(*this);
            int rhs = last_reg_;
            int res = allocReg();
            if (reg_top_ > reg_count_)
                reg_count_ = reg_top_;
            chunk.emit(makeABC((uint8_t)charToOp(s.op), (uint8_t)res, (uint8_t)cur, (uint8_t)rhs));
            chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)res, chunk.addIdentifier(s.name)));
        }
        reg_top_ = saved;
        return;
    }
    // Global scope — assignment without var/global is not allowed
    throw std::runtime_error("line " + std::to_string(s.line > 0 ? s.line : current_line_) + ": undeclared variable '" +
                             s.name + "' (use 'var' or 'global')");
}

void Compiler::visit(const ExprStmt& s) {
    noteLine(s.line);
    int saved = reg_top_;
    s.expr->accept(*this);
    reg_top_ = saved;
}

void Compiler::visit(const ThrowStmt& s) {
    noteLine(s.line);
    int saved = reg_top_;
    s.value->accept(*this);
    int r = last_reg_;
    chunk.emit(makeABC((uint8_t)Op::THROW, (uint8_t)r, 0, 0));
    reg_top_ = saved;
}

void Compiler::visit(const TryCatchStmt& s) {
    noteLine(s.line);
    int catch_r = s.catch_var.empty() ? 0 : local_regs_.at(s.catch_var);

    size_t try_patch = chunk.emitJump(Op::TRY, (uint8_t)catch_r);

    for (auto& stmt : s.try_body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }

    chunk.emit(makeBx((uint8_t)Op::POP_TRY, 0));
    size_t else_patch = chunk.emitJump(Op::JUMP);

    uint16_t catch_addr = (uint16_t)chunk.currentPos();
    chunk.patchJump(try_patch, catch_addr);

    for (auto& stmt : s.catch_body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }
    size_t end_patch = chunk.emitJump(Op::JUMP);

    uint16_t else_addr = (uint16_t)chunk.currentPos();
    chunk.patchJump(else_patch, else_addr);

    for (auto& stmt : s.else_body) {
        int s2 = reg_top_;
        stmt->accept(*this);
        reg_top_ = s2;
    }

    uint16_t end_addr = (uint16_t)chunk.currentPos();
    chunk.patchJump(end_patch, end_addr);
}

void Compiler::visit(const FuncDeclStmt& s) {
    noteLine(s.line);
    // Save outer context
    auto outer_regs = std::move(local_regs_);
    auto outer_upvals = std::move(cur_upval_idx_);
    int outer_top = reg_top_;
    int outer_count = reg_count_;
    int outer_locals = locals_top_;
    auto outer_name = current_func_name;
    int outer_fidx = current_func_idx_;
    bool is_nested = !outer_name.empty(); // déclarée dans une autre fonction

    auto outer_consts = const_names_; // copy (not move) — stays in OuterScope too
    const_names_.clear();

    // Push outer scope for upvalue resolution
    outer_scopes_.push_back({outer_regs, outer_upvals, outer_consts, outer_fidx});

    current_func_name = s.name;
    cur_upval_idx_.clear();
    local_regs_.clear();
    reg_top_ = 0;
    reg_count_ = 0;
    locals_top_ = 0;

    // Assign parameter registers
    int n_fixed = (int)s.params.size();
    for (int i = 0; i < n_fixed; ++i)
        local_regs_[s.params[i]] = i;
    reg_top_ = n_fixed;

    // Pre-scan body for all var declarations and for-loop variables
    // Seed with param names so redeclaring a param with 'var' is caught
    std::vector<std::string> body_locals(s.params.begin(), s.params.end());
    collectLocals(s.body, body_locals);
    for (auto& name : body_locals) {
        if (!local_regs_.count(name))
            local_regs_[name] = reg_top_++;
    }
    locals_top_ = reg_top_;
    reg_count_ = reg_top_;

    // Emit jump over function body
    size_t jump_patch = chunk.emitJump(Op::JUMP);
    uint32_t func_addr = (uint32_t)chunk.currentPos();

    // Build default values
    std::vector<Value> defs(n_fixed);
    for (int i = 0; i < n_fixed; ++i)
        defs[i] = (i < (int)s.defaults.size() && s.defaults[i]) ? evalConstant(*s.defaults[i]) : Value{};
    uint16_t defaults_idx = chunk.addFuncDefaults(std::move(defs));

    FuncProto fp{func_addr, (uint8_t)n_fixed, s.variadic, false, defaults_idx, 0, {}};
    uint8_t func_idx = chunk.addFunc(fp);
    current_func_idx_ = func_idx;

    bool outer_has_vars = !outer_scopes_.back().regs.empty();

    if (!is_nested) {
        // Fonction top-level : pré-marque dans func_table pour optimiser les appels
        // récursifs (CALL_DYN au lieu de CALL_FUNC quand la fonction peut être closure)
        func_table[s.name] = FuncInfo{func_idx, n_fixed, s.variadic, outer_has_vars};
    }
    // Fonctions imbriquées : pas de func_table — elles vivent dans un registre local

    // Compile body
    for (auto& stmt : s.body) {
        int saved = reg_top_;
        stmt->accept(*this);
        reg_top_ = saved;
    }
    emitImplicitReturn(chunk); // implicit void return (omis si le corps finit déjà par RETURN)

    // Update reg_count in FuncProto
    if (reg_count_ > 255)
        throw std::runtime_error("function uses more than 255 registers");
    chunk.funcs[func_idx].reg_count = (uint8_t)reg_count_;

    // Patch jump over body
    chunk.patchJump(jump_patch, (uint16_t)chunk.currentPos());

    // Pop scope and restore outer context
    outer_scopes_.pop_back();
    local_regs_ = std::move(outer_regs);
    cur_upval_idx_ = std::move(outer_upvals);
    const_names_ = std::move(outer_consts);
    reg_top_ = outer_top;
    reg_count_ = outer_count;
    locals_top_ = outer_locals;
    current_func_name = outer_name;
    current_func_idx_ = outer_fidx;

    bool has_upvals = !chunk.funcs[func_idx].upvals.empty();

    if (is_nested) {
        // Fonction imbriquée : stockée dans le registre local pré-alloué par collectLocals.
        // Aucune entrée dans func_table, aucun accès aux globaux.
        int dest = local_regs_.at(s.name);
        if (has_upvals) {
            chunk.emit(makeABx((uint8_t)Op::MAKE_CLOSURE, (uint8_t)dest, func_idx));
        } else {
            chunk.emit(makeABx((uint8_t)Op::LOAD_FUNC, (uint8_t)dest, func_idx));
        }
    } else if (has_upvals) {
        // Fonction top-level closure : MAKE_CLOSURE + STORE_GLOBAL
        func_table[s.name].is_closure = true;
        int tmp = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        chunk.emit(makeABx((uint8_t)Op::MAKE_CLOSURE, (uint8_t)tmp, func_idx));
        chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)tmp, chunk.addIdentifier(s.name)));
        reg_top_--;
    } else {
        // Fonction top-level non-closure : LOAD_FUNC + STORE_GLOBAL.
        // Nécessaire même sans outer vars pour que getGlobal("draw") fonctionne
        // (auto-détection WASM) et pour que la fonction soit accessible comme valeur.
        func_table[s.name].is_closure = false;
        int tmp = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        chunk.emit(makeABx((uint8_t)Op::LOAD_FUNC, (uint8_t)tmp, func_idx));
        chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)tmp, chunk.addIdentifier(s.name)));
        reg_top_--;
    }
}

void Compiler::visit(const FuncExpr& s) {
    auto outer_regs = std::move(local_regs_);
    auto outer_upvals = std::move(cur_upval_idx_);
    int outer_top = reg_top_;
    int outer_count = reg_count_;
    int outer_locals = locals_top_;
    auto outer_name = current_func_name;
    int outer_fidx = current_func_idx_;
    auto outer_consts = const_names_;
    const_names_.clear();

    outer_scopes_.push_back({outer_regs, outer_upvals, outer_consts, outer_fidx});

    current_func_name = "<lambda>";
    cur_upval_idx_.clear();
    local_regs_.clear();
    reg_top_ = 0;
    reg_count_ = 0;
    locals_top_ = 0;

    int n_fixed = (int)s.params.size();
    for (int i = 0; i < n_fixed; ++i)
        local_regs_[s.params[i]] = i;
    reg_top_ = n_fixed;

    std::vector<std::string> body_locals(s.params.begin(), s.params.end());
    collectLocals(s.body, body_locals);
    for (auto& nm : body_locals)
        if (!local_regs_.count(nm))
            local_regs_[nm] = reg_top_++;
    locals_top_ = reg_top_;
    reg_count_ = reg_top_;

    size_t jump_patch = chunk.emitJump(Op::JUMP);
    uint32_t func_addr = (uint32_t)chunk.currentPos();

    std::vector<Value> defs(n_fixed);
    for (int i = 0; i < n_fixed; ++i)
        defs[i] = (i < (int)s.defaults.size() && s.defaults[i]) ? evalConstant(*s.defaults[i]) : Value{};
    uint16_t defaults_idx = chunk.addFuncDefaults(std::move(defs));

    FuncProto fp{func_addr, (uint8_t)n_fixed, s.variadic, false, defaults_idx, 0, {}};
    uint8_t func_idx = chunk.addFunc(fp);
    current_func_idx_ = func_idx;

    for (auto& stmt : s.body) {
        int saved = reg_top_;
        stmt->accept(*this);
        reg_top_ = saved;
    }
    emitImplicitReturn(chunk);
    if (reg_count_ > 255)
        throw std::runtime_error("function uses more than 255 registers");
    chunk.funcs[func_idx].reg_count = (uint8_t)reg_count_;
    chunk.patchJump(jump_patch, (uint16_t)chunk.currentPos());

    outer_scopes_.pop_back();
    local_regs_ = std::move(outer_regs);
    cur_upval_idx_ = std::move(outer_upvals);
    const_names_ = std::move(outer_consts);
    reg_top_ = outer_top;
    reg_count_ = outer_count;
    locals_top_ = outer_locals;
    current_func_name = outer_name;
    current_func_idx_ = outer_fidx;

    bool has_upvals = !chunk.funcs[func_idx].upvals.empty();
    int dest = reg_top_++;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;
    chunk.emit(makeABx(has_upvals ? (uint8_t)Op::MAKE_CLOSURE : (uint8_t)Op::LOAD_FUNC, (uint8_t)dest, func_idx));
    last_reg_ = dest;
}

// Compile chaque expression dans base+i (cf. déclaration).
void Compiler::compileConsecutive(int base, const std::vector<std::unique_ptr<Expr>>& exprs) {
    for (int i = 0; i < (int)exprs.size(); ++i) {
        int target = base + i;
        reg_top_ = target;
        exprs[i]->accept(*this);
        if (last_reg_ != target)
            chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)target, (uint8_t)last_reg_, 0));
        reg_top_ = target + 1;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
    }
}

void Compiler::visit(const ReturnStmt& s) {
    noteLine(s.line);
    if (!inFunction())
        throw std::runtime_error("line " + std::to_string(s.line) + ": return outside function");
    if (s.spread_varargs) {
        int base = reg_top_;
        compileConsecutive(base, s.values);
        chunk.emit(makeABC((uint8_t)Op::RETURN_V, (uint8_t)base, (uint8_t)s.values.size(), 0));
    } else {
        int n = (int)s.values.size();
        if (n == 0) {
            chunk.emit(makeABC((uint8_t)Op::RETURN, 0, 0, 0));
        } else {
            int base = reg_top_;
            compileConsecutive(base, s.values);
            chunk.emit(makeABC((uint8_t)Op::RETURN, (uint8_t)base, (uint8_t)n, 0));
        }
    }
}

// ── expressions ───────────────────────────────────────────────────────────────

void Compiler::visit(const NumberExpr& e) {
    last_reg_ = allocReg();
    chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_,
                       chunk.addConstant(e.is_integer ? Value(e.ival) : numValue(e.value))));
}

void Compiler::visit(const StringExpr& e) {
    last_reg_ = allocReg();
    chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_, chunk.addConstant(Value(e.value))));
}

void Compiler::visit(const BoolExpr& e) {
    last_reg_ = allocReg();
    chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)last_reg_, chunk.addConstant(Value((int64_t)(e.value ? 1 : 0)))));
}

void Compiler::visit(const NilExpr&) {
    last_reg_ = allocReg();
    chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)last_reg_, 0, 0));
}

void Compiler::visit(const VarExpr& e) {
    // Local variable shadows everything (including global functions of the same name)
    {
        auto it = local_regs_.find(e.name);
        if (it != local_regs_.end()) {
            last_reg_ = it->second;
            return;
        }
    }
    // Référence à une fonction globale
    auto fit = func_table.find(e.name);
    if (fit != func_table.end()) {
        last_reg_ = allocReg();
        if (fit->second.is_closure) {
            chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)last_reg_, chunk.addIdentifier(e.name)));
        } else {
            chunk.emit(makeABx((uint8_t)Op::LOAD_FUNC, (uint8_t)last_reg_, fit->second.func_idx));
        }
        return;
    }
    // Upvalue
    {
        int uv = resolveUpvalue(e.name);
        if (uv >= 0) {
            last_reg_ = allocReg();
            chunk.emit(makeABC((uint8_t)Op::GET_UPVAL, (uint8_t)last_reg_, (uint8_t)uv, 0));
            return;
        }
    }
    if (!declared_globals_.count(e.name))
        throw std::runtime_error("line " + std::to_string(current_line_) + ": undeclared variable '" + e.name + "'");
    last_reg_ = allocReg();
    chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)last_reg_, chunk.addIdentifier(e.name)));
}

void Compiler::visit(const BinaryExpr& e) {
    // ── and (&) / or (|) : court-circuit — la droite n'est évaluée que si besoin.
    // Sémantique valeur (modèle Lua) : `a and b` = a si a falsy, sinon b ;
    // `a or b` = a si a truthy, sinon b. (Les opcodes AND/OR restent utilisés
    // par les comparaisons chaînées, où les deux côtés sont déjà calculés.)
    if (e.op == '&' || e.op == '|') {
        e.left->accept(*this);
        int rL = last_reg_;
        if (reg_top_ <= rL)
            reg_top_ = rL + 1;
        int dst = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)dst, (uint8_t)rL, 0));
        if (e.op == '&') {
            // a falsy → garder a (dans dst) et sauter l'évaluation de b
            size_t skip = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)dst);
            e.right->accept(*this);
            chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)dst, (uint8_t)last_reg_, 0));
            chunk.patchJump(skip, (uint16_t)chunk.currentPos());
        } else {
            // a truthy → garder a ; a falsy → évaluer b
            size_t evalRight = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)dst);
            size_t done = chunk.emitJump(Op::JUMP);
            chunk.patchJump(evalRight, (uint16_t)chunk.currentPos());
            e.right->accept(*this);
            chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)dst, (uint8_t)last_reg_, 0));
            chunk.patchJump(done, (uint16_t)chunk.currentPos());
        }
        reg_top_ = dst + 1;
        last_reg_ = dst;
        return;
    }
    e.left->accept(*this);
    int rL = last_reg_;
    // protéger le registre du résultat gauche : un appel 0-arg (ou toute expr
    // qui laisse reg_top_ <= rL) verrait sinon l'opérande droit le réécraser.
    if (reg_top_ <= rL)
        reg_top_ = rL + 1;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;
    e.right->accept(*this);
    int rR = last_reg_;
    last_reg_ = reg_top_++;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;

    chunk.emit(makeABC((uint8_t)binaryArithOpcode(e.op), (uint8_t)last_reg_, (uint8_t)rL, (uint8_t)rR));
}

// a < b < c  →  chaque opérande dans un registre dédié, comparaisons pairées, AND final
void Compiler::visit(const ChainedCompareExpr& e) {
    int n = (int)e.operands.size(); // n opérandes, n-1 opérateurs

    // évaluer tous les opérandes dans des registres temporaires contigus
    int base_tmp = reg_top_;
    std::vector<int> regs;
    for (int i = 0; i < n; i++) {
        e.operands[i]->accept(*this);
        regs.push_back(last_reg_);
        if (last_reg_ >= reg_top_) {
            reg_top_ = last_reg_ + 1;
            if (reg_top_ > reg_count_)
                reg_count_ = reg_top_;
        }
    }

    // allouer n-1 registres de résultat de comparaison
    int cmp_base = reg_top_;
    reg_top_ += n - 1;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;

    static auto cmpOp = [](char op) -> uint8_t {
        switch (op) {
        case '=':
            return (uint8_t)Op::EQ;
        case 'N':
            return (uint8_t)Op::NEQ;
        case '>':
            return (uint8_t)Op::GT;
        case '<':
            return (uint8_t)Op::LT;
        case 'G':
            return (uint8_t)Op::GE;
        case 'L':
            return (uint8_t)Op::LE;
        default:
            throw std::runtime_error("unknown cmp op in chain");
        }
    };

    for (int i = 0; i < n - 1; i++)
        chunk.emit(makeABC(cmpOp(e.ops[i]), (uint8_t)(cmp_base + i), (uint8_t)regs[i], (uint8_t)regs[i + 1]));

    // AND itératif des résultats partiels dans cmp_base
    for (int i = 1; i < n - 1; i++)
        chunk.emit(makeABC((uint8_t)Op::AND, (uint8_t)cmp_base, (uint8_t)cmp_base, (uint8_t)(cmp_base + i)));

    last_reg_ = cmp_base;
    reg_top_ = base_tmp; // libère tous les temporaires après l'expression
}

void Compiler::visit(const UnaryExpr& e) {
    e.operand->accept(*this);
    int rIn = last_reg_;
    last_reg_ = allocReg();
    chunk.emit(makeABC((uint8_t)unaryOpcode(e.op), (uint8_t)last_reg_, (uint8_t)rIn, 0));
}

void Compiler::visit(const CallExpr& e) {
    if (e.optional) {
        // appel optionnel nommé : callee résolu AVANT les args, garde, puis args
        int call_base = reg_top_;
        int argc = (int)e.args.size();
        int func_reg = call_base + argc;
        reg_top_ = call_base + 1;
        {
            auto rit = local_regs_.find(e.callee);
            if (rit != local_regs_.end()) {
                chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)call_base, (uint8_t)rit->second, 0));
            } else {
                int uv = resolveUpvalue(e.callee);
                if (uv >= 0)
                    chunk.emit(makeABC((uint8_t)Op::GET_UPVAL, (uint8_t)call_base, (uint8_t)uv, 0));
                else
                    chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)call_base, chunk.addIdentifier(e.callee)));
            }
        }
        reg_top_ = func_reg + 1;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        // f?(args) ≡ if f then f(args) else nil  — JUMP_IF_FALSE (nil est falsy) saute
        // les args : ils ne sont donc PAS évalués si f est falsy.
        size_t to_nil = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)call_base);
        chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)func_reg, (uint8_t)call_base, 0));
        for (int i = 0; i < argc; ++i) {
            reg_top_ = func_reg + 1;
            compileInto(*e.args[i], call_base + i);
        }
        reg_top_ = func_reg + 1;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        chunk.emit(makeABC((uint8_t)Op::CALL_DYN, (uint8_t)call_base, (uint8_t)func_reg, (uint8_t)argc));
        size_t to_end = chunk.emitJump(Op::JUMP);
        chunk.patchJump(to_nil, (uint16_t)chunk.currentPos());
        chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)call_base, 0, 0));
        chunk.patchJump(to_end, (uint16_t)chunk.currentPos());
        reg_top_ = call_base + 1;
        last_reg_ = call_base;
        return;
    }

    // Check if it's a user-defined function
    auto it = func_table.find(e.callee);
    if (it != func_table.end()) {
        int call_base = reg_top_;
        int argc = (int)e.args.size();
        compileConsecutive(call_base, e.args);
        if (it->second.is_closure) {
            int func_reg = reg_top_++;
            if (reg_top_ > reg_count_)
                reg_count_ = reg_top_;
            chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)func_reg, chunk.addIdentifier(e.callee)));
            chunk.emit(makeABC((uint8_t)Op::CALL_DYN, (uint8_t)call_base, (uint8_t)func_reg, (uint8_t)argc));
        } else {
            chunk.emit(makeABC((uint8_t)Op::CALL_FUNC, (uint8_t)call_base, it->second.func_idx, (uint8_t)argc));
        }
        last_reg_ = call_base;
        return;
    }

    // Builtins
    int call_base = reg_top_;
    int argc = (int)e.args.size();
    compileConsecutive(call_base, e.args);

    // Tous les appels passent par CALL_DYN — builtins sont des globaux T_BUILTIN
    {
        int func_reg = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        {
            auto rit = local_regs_.find(e.callee);
            if (rit != local_regs_.end()) {
                func_reg = rit->second;
                reg_top_--;
            } else {
                int uv = resolveUpvalue(e.callee);
                if (uv >= 0) {
                    chunk.emit(makeABC((uint8_t)Op::GET_UPVAL, (uint8_t)func_reg, (uint8_t)uv, 0));
                } else {
                    chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)func_reg, chunk.addIdentifier(e.callee)));
                }
            }
        }
        chunk.emit(makeABC((uint8_t)Op::CALL_DYN, (uint8_t)call_base, (uint8_t)func_reg, (uint8_t)argc));
        last_reg_ = call_base;
    }
}

void Compiler::visit(const ExprCallExpr& e) {
    int call_base = reg_top_;
    int argc = (int)e.args.size();

    if (e.optional) {
        // appel optionnel : évaluer le callee AVANT les args, garde, puis args
        int func_reg = call_base + argc;
        reg_top_ = call_base + 1;
        compileInto(*e.callee, call_base); // callee dans call_base (check+résultat)
        reg_top_ = func_reg + 1;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        // f?(args) ≡ if f then f(args) else nil — JUMP_IF_FALSE saute les args (non évalués)
        size_t to_nil = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)call_base);
        chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)func_reg, (uint8_t)call_base, 0));
        for (int i = 0; i < argc; ++i) { // temps au-dessus de func_reg
            reg_top_ = func_reg + 1;
            compileInto(*e.args[i], call_base + i);
        }
        reg_top_ = func_reg + 1;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        chunk.emit(makeABC((uint8_t)Op::CALL_DYN, (uint8_t)call_base, (uint8_t)func_reg, (uint8_t)argc));
        size_t to_end = chunk.emitJump(Op::JUMP);
        chunk.patchJump(to_nil, (uint16_t)chunk.currentPos());
        chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)call_base, 0, 0));
        chunk.patchJump(to_end, (uint16_t)chunk.currentPos());
        reg_top_ = call_base + 1;
        last_reg_ = call_base;
        return;
    }

    // Compile args into consecutive registers
    compileConsecutive(call_base, e.args);

    // Compile callee into a temp register after args
    int func_reg = reg_top_++;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;
    compileInto(*e.callee, func_reg);

    chunk.emit(makeABC((uint8_t)Op::CALL_DYN, (uint8_t)call_base, (uint8_t)func_reg, (uint8_t)argc));
    last_reg_ = call_base;
}

void Compiler::visit(const VarArgExpr&) {
    if (!inFunction())
        throw std::runtime_error("line " + std::to_string(current_line_) + ": ... outside a variadic function");
    int base = reg_top_;
    chunk.emit(makeABC((uint8_t)Op::LOAD_VARARGS, (uint8_t)base, 0, 0));
    last_reg_ = base;
}

void Compiler::visit(const MapExpr& e) {
    int dest = allocReg();
    chunk.emit(makeABC((uint8_t)Op::NEW_MAP, (uint8_t)dest, 0, 0));
    for (auto& entry : e.entries) {
        int saved = reg_top_;
        int key_reg = allocReg();
        compileInto(*entry.key, key_reg); // StringExpr littéral OU clé calculée
        int val_reg = allocReg();
        compileInto(*entry.value, val_reg);
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_reg, (uint8_t)val_reg));
        reg_top_ = saved;
    }
    last_reg_ = dest;
}

void Compiler::visit(const IndexExpr& e) {
    int saved = reg_top_;
    e.obj->accept(*this);
    int obj_r = last_reg_;
    // Réserver le registre objet avant d'évaluer la clé : un appel 0-argument
    // laisse reg_top_ == son registre résultat, donc sans cette garde l'évaluation
    // de la clé réalloue et écrase l'objet (cf. BinaryExpr). Ex. : f().x, f()[i].
    if (reg_top_ <= obj_r)
        reg_top_ = obj_r + 1;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;
    int saved2 = reg_top_;
    e.key->accept(*this);
    int key_r = last_reg_;
    reg_top_ = saved2;
    int dest = allocReg();
    chunk.emit(makeABC((uint8_t)Op::GET_INDEX, (uint8_t)dest, (uint8_t)obj_r, (uint8_t)key_r));
    last_reg_ = dest;
    (void)saved;
}

void Compiler::visit(const ArrayExpr& e) {
    int dest = allocReg();
    chunk.emit(makeABC((uint8_t)Op::NEW_ARRAY, (uint8_t)dest, 0, 0));
    for (auto& elem : e.elements) {
        int saved = reg_top_;
        int val_r = allocReg();
        compileInto(*elem, val_r);
        chunk.emit(makeABC((uint8_t)Op::ARRAY_PUSH, (uint8_t)dest, (uint8_t)val_r, 0));
        reg_top_ = saved;
    }
    last_reg_ = dest;
}

void Compiler::visit(const RangeExpr& e) {
    // Allocate dest first, then use temps above it
    int dest = allocReg(); // dest = reg_top_-1

    // Temps: base = dest+1 for start, base+1 for end, base+2 for step
    int base = reg_top_; // = dest+1

    // Compile start
    int start_r = base;
    reg_top_ = base + 1;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;
    compileInto(*e.start, start_r);

    // Compile end
    int end_r = base + 1;
    reg_top_ = base + 2;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;
    compileInto(*e.end, end_r);

    // Compile step if present
    bool has_step = (e.step != nullptr);
    if (has_step) {
        int step_r = base + 2;
        reg_top_ = base + 3;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        compileInto(*e.step, step_r);
    }

    // If open-left: adjust start = start + step_or_1
    if (!e.incl_left) {
        if (has_step) {
            chunk.emit(makeABC((uint8_t)Op::ADD, (uint8_t)start_r, (uint8_t)start_r, (uint8_t)(base + 2)));
        } else {
            int one_r = base + 2;
            reg_top_ = base + 3;
            if (reg_top_ > reg_count_)
                reg_count_ = reg_top_;
            chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)one_r, chunk.addConstant(Value((int64_t)1))));
            chunk.emit(makeABC((uint8_t)Op::ADD, (uint8_t)start_r, (uint8_t)start_r, (uint8_t)one_r));
        }
    }

    // Build flags: bit0 = incl_right, bit1 = has_step
    uint8_t flags = (uint8_t)((has_step ? 2 : 0) | (e.incl_right ? 1 : 0));

    chunk.emit(makeABC((uint8_t)Op::MAKE_RANGE, (uint8_t)dest, (uint8_t)base, flags));

    // Restore reg_top_ to dest+1 (temps freed, dest still "live")
    reg_top_ = dest + 1;
    last_reg_ = dest;
}

static bool bodyHasFunc(const std::vector<std::unique_ptr<Stmt>>& body); // défini plus bas

void Compiler::compileIteratorLoop(const Expr& src, const std::string& var1, const std::string& var2,
                                   const std::vector<std::unique_ptr<Stmt>>& body) {
    bool two_vars = !var2.empty();
    int block = reg_top_;
    int tmp_src = block + (two_vars ? 3 : 2);
    reg_top_ = tmp_src + 1;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;

    compileInto(src, tmp_src); // src compilé AVANT de scoper les variables de boucle
    chunk.emit(makeABC((uint8_t)Op::MAKE_ITER, (uint8_t)block, (uint8_t)tmp_src, 0));
    reg_top_ = tmp_src;

    // Variables de boucle scopées : on les aliase directement sur les registres où
    // FOR_ITER_NEXT écrit (block+1 = clé/primaire, block+2 = val). Pas de copie : la
    // valeur est réécrite à chaque tour (modifier la variable dans le corps est donc
    // sans effet). Liaisons sauvegardées puis restaurées → aucune fuite après la boucle.
    auto saveBind = [&](const std::string& n, int reg, bool& had, int& old) {
        auto it = local_regs_.find(n);
        had = (it != local_regs_.end());
        old = had ? it->second : -1;
        local_regs_[n] = reg;
    };
    auto restoreBind = [&](const std::string& n, bool had, int old) {
        if (had)
            local_regs_[n] = old;
        else
            local_regs_.erase(n);
    };
    bool had1, had2 = false;
    int old1, old2 = -1;
    saveBind(var1, block + 1, had1, old1);
    if (two_vars)
        saveBind(var2, block + 2, had2, old2);

    auto loop_start = (uint16_t)chunk.currentPos();
    Op iter_op = two_vars ? Op::FOR_ITER_NEXT : Op::FOR_ITER_NEXT1;
    size_t exit_patch = chunk.emitJump(iter_op, (uint8_t)block);

    break_patches.push_back({});
    continue_patches.push_back({});
    for (auto& stmt : body) {
        int saved = reg_top_;
        stmt->accept(*this);
        reg_top_ = saved;
    }
    for (size_t p : continue_patches.back())
        chunk.patchJump(p, loop_start);
    continue_patches.pop_back();
    chunk.emit(makeBx((uint8_t)Op::JUMP, loop_start));

    uint16_t exit = (uint16_t)chunk.currentPos();
    chunk.patchJump(exit_patch, exit);
    for (size_t p : break_patches.back())
        chunk.patchJump(p, exit);
    break_patches.pop_back();

    restoreBind(var1, had1, old1); // restaure la portée (pas de fuite)
    if (two_vars)
        restoreBind(var2, had2, old2);
    // recyclage : si une closure capture la variable de boucle, garder ses registres
    // réservés (sinon réécrits après la boucle → upvalue corrompue).
    reg_top_ = bodyHasFunc(body) ? (block + (two_vars ? 3 : 2)) : block;
}

void Compiler::visit(const ForIterStmt& s) {
    noteLine(s.line);
    // chemin rapide : for i in <range littéral inclus aux deux bornes>, 1 variable
    // (couvre la forme `for i = a, b[, step]`). Évite Range + itérateur + dispatch virtuel.
    if (s.var2.empty()) {
        if (auto* r = dynamic_cast<const RangeExpr*>(s.iter_expr.get())) {
            if (r->incl_left && r->incl_right) {
                compileNumericFor(*r, s.var1, s.body);
                return;
            }
        }
    }
    compileIteratorLoop(*s.iter_expr, s.var1, s.var2, s.body);
}

// ── analyse de sûreté pour aliaser la variable de boucle au registre de contrôle ──
// Vrai si l'expression contient une lambda (capture potentielle de la var de boucle).
static bool exprHasLambda(const Expr* e) {
    if (!e)
        return false;
    if (dynamic_cast<const FuncExpr*>(e))
        return true;
    if (auto* b = dynamic_cast<const BinaryExpr*>(e))
        return exprHasLambda(b->left.get()) || exprHasLambda(b->right.get());
    if (auto* u = dynamic_cast<const UnaryExpr*>(e))
        return exprHasLambda(u->operand.get());
    if (auto* c = dynamic_cast<const CallExpr*>(e)) {
        for (auto& a : c->args)
            if (exprHasLambda(a.get()))
                return true;
        return false;
    }
    if (auto* c = dynamic_cast<const ExprCallExpr*>(e)) {
        if (exprHasLambda(c->callee.get()))
            return true;
        for (auto& a : c->args)
            if (exprHasLambda(a.get()))
                return true;
        return false;
    }
    if (auto* m = dynamic_cast<const MethodCallExpr*>(e)) {
        if (exprHasLambda(m->receiver.get()))
            return true;
        for (auto& a : m->args)
            if (exprHasLambda(a.get()))
                return true;
        return false;
    }
    if (auto* i = dynamic_cast<const IndexExpr*>(e))
        return exprHasLambda(i->obj.get()) || exprHasLambda(i->key.get());
    if (auto* mp = dynamic_cast<const MapExpr*>(e)) {
        for (auto& en : mp->entries)
            if (exprHasLambda(en.key.get()) || exprHasLambda(en.value.get()))
                return true;
        return false;
    }
    if (auto* ar = dynamic_cast<const ArrayExpr*>(e)) {
        for (auto& x : ar->elements)
            if (exprHasLambda(x.get()))
                return true;
        return false;
    }
    if (auto* rg = dynamic_cast<const RangeExpr*>(e))
        return exprHasLambda(rg->start.get()) || exprHasLambda(rg->end.get()) || exprHasLambda(rg->step.get());
    if (auto* cc = dynamic_cast<const ChainedCompareExpr*>(e)) {
        for (auto& o : cc->operands)
            if (exprHasLambda(o.get()))
                return true;
        return false;
    }
    if (dynamic_cast<const VarExpr*>(e) || dynamic_cast<const NumberExpr*>(e) || dynamic_cast<const StringExpr*>(e) ||
        dynamic_cast<const BoolExpr*>(e) || dynamic_cast<const NilExpr*>(e) || dynamic_cast<const VarArgExpr*>(e))
        return false;
    return true; // type inconnu → conservatif
}

// Vrai si le corps est sûr pour aliaser la var de boucle 'v' au registre de contrôle :
// aucune réassignation de v, aucune lambda, aucune structure de contrôle imbriquée
// (conservatif — couvre les corps « feuilles » comme s += i).
static bool loopBodyAliasSafe(const std::vector<std::unique_ptr<Stmt>>& body, const std::string& v) {
    for (auto& sp : body) {
        const Stmt* s = sp.get();
        if (auto* a = dynamic_cast<const AssignStmt*>(s)) {
            if (a->name == v)
                return false;
            if (exprHasLambda(a->value.get()))
                return false;
        } else if (auto* m = dynamic_cast<const MultiAssignStmt*>(s)) {
            for (auto& t : m->targets) {
                if (t.kind == LValue::VAR && t.name == v)
                    return false;
                if (t.key && exprHasLambda(t.key.get()))
                    return false;
            }
            for (auto& val : m->values)
                if (exprHasLambda(val.get()))
                    return false;
        } else if (auto* d = dynamic_cast<const VarDeclStmt*>(s)) {
            for (auto& n : d->names)
                if (n == v)
                    return false; // shadow
            for (auto& val : d->values)
                if (exprHasLambda(val.get()))
                    return false;
        } else if (auto* e = dynamic_cast<const ExprStmt*>(s)) {
            if (exprHasLambda(e->expr.get()))
                return false;
        } else if (auto* r = dynamic_cast<const ReturnStmt*>(s)) {
            for (auto& x : r->values)
                if (exprHasLambda(x.get()))
                    return false;
        } else if (auto* th = dynamic_cast<const ThrowStmt*>(s)) {
            if (exprHasLambda(th->value.get()))
                return false;
        } else if (auto* ia = dynamic_cast<const IndexAssignStmt*>(s)) {
            // obj==v n'écrit pas v (écrit dans son conteneur) ; vérifier key/value
            // et le conteneur chaîné éventuel (obj_expr).
            if (exprHasLambda(ia->key.get()) || exprHasLambda(ia->value.get()) ||
                (ia->obj_expr && exprHasLambda(ia->obj_expr.get())))
                return false;
        } else if (dynamic_cast<const BreakStmt*>(s) || dynamic_cast<const ContinueStmt*>(s) ||
                   dynamic_cast<const CommentStmt*>(s)) {
            // sûr
        } else {
            return false; // if/while/for/block/try/switch/funcdecl/… → conservatif
        }
    }
    return true;
}

// Vrai si le corps contient une fonction/closure (n'importe où, récursivement).
// Sert à décider si on peut recycler les registres de boucle à la sortie : une
// closure peut capturer (upvalue ouverte) le registre de la variable de boucle ;
// dans ce cas on le garde réservé pour qu'il ne soit pas réécrit après la boucle.
static bool bodyHasFunc(const std::vector<std::unique_ptr<Stmt>>& body);
struct HasFuncQuery : StmtQuery {
    bool result = false;
    void visit(const FuncDeclStmt&) override {
        result = true;
    }
    void visit(const SwitchStmt&) override {
        result = true; // conservatif
    }
    void visit(const ClassDeclStmt&) override {
        result = true; // conservatif
    }
    void visit(const AssignStmt& s) override {
        result = exprHasLambda(s.value.get());
    }
    void visit(const ExprStmt& s) override {
        result = exprHasLambda(s.expr.get());
    }
    void visit(const ThrowStmt& s) override {
        result = exprHasLambda(s.value.get());
    }
    void visit(const IndexAssignStmt& s) override {
        result = exprHasLambda(s.key.get()) || exprHasLambda(s.value.get()) ||
                 (s.obj_expr && exprHasLambda(s.obj_expr.get()));
    }
    void visit(const MultiAssignStmt& s) override {
        for (auto& v : s.values)
            if (exprHasLambda(v.get())) {
                result = true;
                return;
            }
        for (auto& t : s.targets)
            if (t.key && exprHasLambda(t.key.get())) {
                result = true;
                return;
            }
    }
    void visit(const VarDeclStmt& s) override {
        for (auto& v : s.values)
            if (exprHasLambda(v.get())) {
                result = true;
                return;
            }
    }
    void visit(const ReturnStmt& s) override {
        for (auto& v : s.values)
            if (exprHasLambda(v.get())) {
                result = true;
                return;
            }
    }
    void visit(const WhileStmt& s) override {
        result = exprHasLambda(s.cond.get()) || bodyHasFunc(s.body);
    }
    void visit(const ForIterStmt& s) override {
        result = exprHasLambda(s.iter_expr.get()) || bodyHasFunc(s.body);
    }
    void visit(const TryCatchStmt& s) override {
        result = bodyHasFunc(s.try_body) || bodyHasFunc(s.catch_body) || bodyHasFunc(s.else_body);
    }
    void visit(const BlockStmt& s) override {
        result = bodyHasFunc(s.stmts);
    }
    void visit(const IfStmt& s) override {
        if (exprHasLambda(s.cond.get()) || bodyHasFunc(s.then_body) || bodyHasFunc(s.else_body)) {
            result = true;
            return;
        }
        for (auto& ei : s.else_ifs)
            if (exprHasLambda(ei.cond.get()) || bodyHasFunc(ei.body)) {
                result = true;
                return;
            }
    }
    // BreakStmt, ContinueStmt, CommentStmt → no-op hérité de StmtQuery (result reste false)
};
static bool stmtHasFunc(const Stmt* s) {
    HasFuncQuery q;
    s->accept(q);
    return q.result;
}
static bool bodyHasFunc(const std::vector<std::unique_ptr<Stmt>>& body) {
    for (auto& s : body)
        if (stmtHasFunc(s.get()))
            return true;
    return false;
}

void Compiler::compileNumericFor(const RangeExpr& r, const std::string& var1,
                                 const std::vector<std::unique_ptr<Stmt>>& body) {
    int ctl = reg_top_; // ctl, ctl+1, ctl+2 = i, limite, pas
    reg_top_ = ctl + 3;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;

    // bornes compilées AVANT de scoper i (pour que `for i = i, …` lise l'ancien i)
    compileInto(*r.start, ctl);
    compileInto(*r.end, ctl + 1);
    if (r.step)
        compileInto(*r.step, ctl + 2);
    else
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)(ctl + 2), chunk.addConstant(Value((int64_t)1))));
    reg_top_ = ctl + 3;

    // Variable de boucle scopée. Si le corps n'écrit jamais i → aliasée sur ctl
    // (pas de copie). Sinon → registre séparé + copie par tour (le corps peut
    // modifier i sans toucher le compteur, comportement sans effet). Liaison
    // restaurée à la sortie → aucune fuite après la boucle.
    bool can_alias = loopBodyAliasSafe(body, var1);
    int var_reg = ctl;
    if (!can_alias) {
        var_reg = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
    }
    bool had_old;
    int old_reg;
    {
        auto it = local_regs_.find(var1);
        had_old = (it != local_regs_.end());
        old_reg = had_old ? it->second : -1;
    }
    local_regs_[var1] = var_reg;

    size_t prep = chunk.emitJump(Op::FOR_PREP, (uint8_t)ctl); // Bx → sortie si boucle vide (patché)

    uint16_t body_addr = (uint16_t)chunk.currentPos(); // FOR_PREP tombe ici si non vide
    if (!can_alias)
        chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)var_reg, (uint8_t)ctl, 0));

    break_patches.push_back({});
    continue_patches.push_back({});
    for (auto& stmt : body) {
        int saved = reg_top_;
        stmt->accept(*this);
        reg_top_ = saved;
    }

    uint16_t loop_addr = (uint16_t)chunk.currentPos();
    for (size_t p : continue_patches.back())
        chunk.patchJump(p, loop_addr); // continue → FOR_LOOP
    continue_patches.pop_back();
    chunk.emit(makeABx((uint8_t)Op::FOR_LOOP, (uint8_t)ctl, body_addr));

    uint16_t exit_addr = (uint16_t)chunk.currentPos();
    chunk.patchJump(prep, exit_addr); // FOR_PREP saute ici si la boucle est vide
    for (size_t p : break_patches.back())
        chunk.patchJump(p, exit_addr);
    break_patches.pop_back();

    if (had_old)
        local_regs_[var1] = old_reg;
    else
        local_regs_.erase(var1); // restaure la portée
    // recyclage des registres : si une closure du corps capture i, on garde son
    // registre réservé (sinon il serait réécrit après la boucle → upvalue corrompue).
    reg_top_ = bodyHasFunc(body) ? (var_reg + 1) : ctl;
}

void Compiler::visit(const IndexAssignStmt& s) {
    noteLine(s.line);
    int saved = reg_top_;

    // Charge le conteneur (map/array) à indexer.
    int obj_r;
    if (s.obj_expr) {
        // Cible chaînée (a.b.c, a[i][j]…) : le conteneur est une expression, on
        // l'évalue dans un registre. maps/arrays étant des références comptées,
        // le SET_INDEX qui suit mute bien l'objet d'origine.
        obj_r = allocReg();
        compileInto(*s.obj_expr, obj_r);
    } else {
        auto it = local_regs_.find(s.obj);
        if (it != local_regs_.end()) {
            obj_r = it->second;
        } else {
            int uv = resolveUpvalue(s.obj);
            obj_r = allocReg();
            if (uv >= 0) {
                chunk.emit(makeABC((uint8_t)Op::GET_UPVAL, (uint8_t)obj_r, (uint8_t)uv, 0));
            } else {
                if (!declared_globals_.count(s.obj))
                    throw std::runtime_error("line " + std::to_string(s.line > 0 ? s.line : current_line_) +
                                             ": undeclared variable '" + s.obj + "'");
                chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)obj_r, chunk.addIdentifier(s.obj)));
            }
        }
    }

    // Compile key
    int key_r = allocReg();
    compileInto(*s.key, key_r);

    if (s.op == TokenType::EQUALS) {
        // Simple assignment: SET_INDEX obj_r, key_r, val_r
        int val_r = allocReg();
        compileInto(*s.value, val_r);
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)obj_r, (uint8_t)key_r, (uint8_t)val_r));
    } else {
        // Compound assignment: get current, apply op, store back
        int cur_r = allocReg();
        chunk.emit(makeABC((uint8_t)Op::GET_INDEX, (uint8_t)cur_r, (uint8_t)obj_r, (uint8_t)key_r));
        int rhs_r = allocReg();
        compileInto(*s.value, rhs_r);
        int result_r = allocReg();
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        chunk.emit(makeABC((uint8_t)tokenToOp(s.op), (uint8_t)result_r, (uint8_t)cur_r, (uint8_t)rhs_r));
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)obj_r, (uint8_t)key_r, (uint8_t)result_r));
    }
    reg_top_ = saved;
}

void Compiler::visit(const MultiAssignStmt& s) {
    noteLine(s.line);
    int saved = reg_top_;

    // Évalue tous les RHS dans des registres temporaires consécutifs
    int base = reg_top_;
    int n = (int)s.values.size();
    for (int i = 0; i < n; ++i) {
        int r = allocReg();
        compileInto(*s.values[i], r);
    }

    // Assigne chaque cible depuis son temporaire (ou nil si plus de valeurs que de cibles)
    for (int i = 0; i < (int)s.targets.size(); ++i) {
        int val_r = (i < n) ? base + i : allocReg(); // nil si pas de valeur
        const LValue& lv = s.targets[i];

        if (lv.kind == LValue::VAR) {
            auto it = local_regs_.find(lv.name);
            if (it != local_regs_.end()) {
                if (val_r != it->second)
                    chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)it->second, (uint8_t)val_r, 0));
            } else {
                int uv = resolveUpvalue(lv.name);
                if (uv >= 0) {
                    chunk.emit(makeABC((uint8_t)Op::SET_UPVAL, (uint8_t)val_r, (uint8_t)uv, 0));
                } else {
                    chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)val_r, chunk.addIdentifier(lv.name)));
                }
            }
        } else {
            // FIELD ou INDEX : charger l'objet
            int obj_r = allocReg();
            auto it = local_regs_.find(lv.name);
            if (it != local_regs_.end()) {
                obj_r = it->second;
                reg_top_--;
            } else {
                int uv = resolveUpvalue(lv.name);
                if (uv >= 0)
                    chunk.emit(makeABC((uint8_t)Op::GET_UPVAL, (uint8_t)obj_r, (uint8_t)uv, 0));
                else
                    chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)obj_r, chunk.addIdentifier(lv.name)));
            }
            if (lv.kind == LValue::FIELD_INDEX) {
                int field_r = allocReg();
                compileInto(StringExpr(lv.field), field_r);
                int inner_r = allocReg();
                chunk.emit(makeABC((uint8_t)Op::GET_INDEX, (uint8_t)inner_r, (uint8_t)obj_r, (uint8_t)field_r));
                int key_r = allocReg();
                compileInto(*lv.key, key_r);
                chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)inner_r, (uint8_t)key_r, (uint8_t)val_r));
            } else {
                int key_r = allocReg();
                if (lv.kind == LValue::FIELD)
                    compileInto(StringExpr(lv.field), key_r);
                else
                    compileInto(*lv.key, key_r);
                chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)obj_r, (uint8_t)key_r, (uint8_t)val_r));
            }
        }
    }

    reg_top_ = saved;
}

void Compiler::visit(const BlockStmt& s) {
    for (auto& stmt : s.stmts)
        stmt->accept(*this);
}

// ── compileMethodFunc : compile une méthode avec 'self' implicite en R[0] ──────
uint8_t Compiler::compileMethodFunc(const FuncDeclStmt& s) {
    auto outer_regs = std::move(local_regs_);
    auto outer_upvals = std::move(cur_upval_idx_);
    auto outer_consts = const_names_; // copy — stays in OuterScope too
    int outer_top = reg_top_;
    int outer_count = reg_count_;
    int outer_locals = locals_top_;
    auto outer_name = current_func_name;
    int outer_fidx = current_func_idx_;
    const_names_.clear();

    outer_scopes_.push_back({outer_regs, outer_upvals, outer_consts, outer_fidx});

    current_func_name = s.name;
    cur_upval_idx_.clear();
    local_regs_.clear();
    reg_top_ = 0;
    reg_count_ = 0;
    locals_top_ = 0;

    int n_params = (int)s.params.size();
    int n_fixed;

    if (s.is_static) {
        // méthode statique : pas de self, params en R[0..n-1]
        for (int i = 0; i < n_params; ++i)
            local_regs_[s.params[i]] = i;
        n_fixed = n_params;
    } else {
        // méthode d'instance : self en R[0], params en R[1..n]
        local_regs_["self"] = 0;
        for (int i = 0; i < n_params; ++i)
            local_regs_[s.params[i]] = i + 1;
        n_fixed = 1 + n_params;
    }
    reg_top_ = n_fixed;

    std::vector<std::string> body_locals;
    if (!s.is_static)
        body_locals.push_back("self");
    body_locals.insert(body_locals.end(), s.params.begin(), s.params.end());
    collectLocals(s.body, body_locals);
    for (auto& name : body_locals)
        if (!local_regs_.count(name))
            local_regs_[name] = reg_top_++;
    locals_top_ = reg_top_;
    reg_count_ = reg_top_;

    size_t jump_patch = chunk.emitJump(Op::JUMP);
    uint32_t func_addr = (uint32_t)chunk.currentPos();

    // defaults : pour méthode instance, index 0 = self (pas de défaut)
    std::vector<Value> defs(n_fixed);
    int defs_offset = s.is_static ? 0 : 1;
    for (int i = 0; i < n_params; ++i)
        defs[i + defs_offset] = (i < (int)s.defaults.size() && s.defaults[i]) ? evalConstant(*s.defaults[i]) : Value{};
    uint16_t defaults_idx = chunk.addFuncDefaults(std::move(defs));

    FuncProto fp{func_addr, (uint8_t)n_fixed, s.variadic, s.is_static, defaults_idx, 0, {}};
    uint8_t func_idx = chunk.addFunc(fp);
    current_func_idx_ = func_idx;

    for (auto& stmt : s.body) {
        int sv = reg_top_;
        stmt->accept(*this);
        reg_top_ = sv;
    }
    emitImplicitReturn(chunk);

    if (reg_count_ > 255)
        throw std::runtime_error("function uses more than 255 registers");
    chunk.funcs[func_idx].reg_count = (uint8_t)reg_count_;
    chunk.patchJump(jump_patch, (uint16_t)chunk.currentPos());

    outer_scopes_.pop_back();
    local_regs_ = std::move(outer_regs);
    cur_upval_idx_ = std::move(outer_upvals);
    const_names_ = std::move(outer_consts);
    reg_top_ = outer_top;
    reg_count_ = outer_count;
    locals_top_ = outer_locals;
    current_func_name = outer_name;
    current_func_idx_ = outer_fidx;

    return func_idx;
}

// ── visit(ClassDeclStmt) ──────────────────────────────────────────────────────
void Compiler::visit(const ClassDeclStmt& s) {
    noteLine(s.line);
    int saved = reg_top_;

    // Créer la valeur classe (T_CLASS = map vide)
    int dest = reg_top_++;
    if (reg_top_ > reg_count_)
        reg_count_ = reg_top_;
    chunk.emit(makeABC((uint8_t)Op::NEW_CLASS, (uint8_t)dest, 0, 0));

    // Stocker le nom de la classe comme __name__ (utile pour print/debug)
    {
        int key_r = reg_top_++, val_r = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.addConstant(Value(std::string("__name__")))));
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)val_r, chunk.addConstant(Value(s.name))));
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_r, (uint8_t)val_r));
        reg_top_ = dest + 1;
    }

    // Héritage : stocker la classe parente comme __parent__
    if (!s.parent.empty()) {
        int par_r = reg_top_++, key_r = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)par_r, chunk.addIdentifier(s.parent)));
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.addConstant(Value(std::string("__parent__")))));
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_r, (uint8_t)par_r));
        reg_top_ = dest + 1;
    }

    // 'super' dans ces méthodes se résout par la classe parente LEXICALE.
    std::string saved_parent = current_class_parent_;
    current_class_parent_ = s.parent;

    // Compiler chaque méthode et la stocker dans la map classe
    for (auto& method : s.methods) {
        // 'static' interdit sur init et sur les méta-méthodes : ces appels
        // (constructeur, opérateurs) injectent self par construction — un
        // membre statique y produirait un décalage d'arguments silencieux.
        if (method->is_static) {
            if (method->name == "init")
                throw std::runtime_error("line " + std::to_string(method->line) +
                                         ": 'init' cannot be static (a constructor always has 'self')");
            if (method->name.size() >= 2 && method->name[0] == '_' && method->name[1] == '_')
                throw std::runtime_error("line " + std::to_string(method->line) + ": metamethod '" + method->name +
                                         "' cannot be static (operators always have 'self')");
        }
        uint8_t func_idx = compileMethodFunc(*method);
        bool has_upvals = !chunk.funcs[func_idx].upvals.empty();

        int func_r = reg_top_++, key_r = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        if (has_upvals)
            chunk.emit(makeABx((uint8_t)Op::MAKE_CLOSURE, (uint8_t)func_r, func_idx));
        else
            chunk.emit(makeABx((uint8_t)Op::LOAD_FUNC, (uint8_t)func_r, func_idx));
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.addConstant(Value(method->name))));
        chunk.emit(makeABC((uint8_t)Op::SET_INDEX, (uint8_t)dest, (uint8_t)key_r, (uint8_t)func_r));
        reg_top_ = dest + 1;
    }

    current_class_parent_ = saved_parent;

    // Stocker la classe comme global (le nom est déjà dans declared_globals_
    // via le pré-scan collectGlobals — source unique de vérité)
    chunk.emit(makeABx((uint8_t)Op::STORE_GLOBAL, (uint8_t)dest, chunk.addIdentifier(s.name)));

    reg_top_ = saved;
}

// ── visit(MethodCallExpr) ─────────────────────────────────────────────────────
// Layout : R[call_base+0]=self, R[call_base+1]=méthode, R[call_base+2..]=args
// CALL_METHOD décale les args de 1 vers le bas (overwrite méthode) avant l'appel.
void Compiler::visit(const MethodCallExpr& e) {
    int call_base = reg_top_;
    int argc = (int)e.args.size();

    if (e.is_super) {
        // self est en local_regs_["self"] — copier en call_base. Hors méthode,
        // 'self' n'existe pas → diagnostic propre plutôt qu'un crash (map::at).
        auto self_it = local_regs_.find("self");
        if (self_it == local_regs_.end())
            throw std::runtime_error("line " + std::to_string(current_line_) +
                                     ": 'super' n'est utilisable que dans une méthode");
        // La classe parente est fixée LEXICALEMENT (classe où la méthode est
        // définie), et non via self.__class__.__parent__ : sinon B.m() exécuté sur
        // une instance C reverrait toujours sur B → récursion infinie dans une
        // hiérarchie à 3+ niveaux.
        if (current_class_parent_.empty())
            throw std::runtime_error("line " + std::to_string(current_line_) +
                                     ": 'super' : la classe courante n'a pas de parent");
        int self_src = self_it->second;
        reg_top_ = call_base + 1;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        chunk.emit(makeABC((uint8_t)Op::MOVE, (uint8_t)call_base, (uint8_t)self_src, 0));

        // Temporaires : tmp = classe parente (globale), key_r = clé
        int tmp = reg_top_++, key_r = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;

        // tmp = <classe parente lexicale>
        chunk.emit(makeABx((uint8_t)Op::LOAD_GLOBAL, (uint8_t)tmp, chunk.addIdentifier(current_class_parent_)));
        // R[call_base+1] = tmp.<method>
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.addConstant(Value(std::string(e.method)))));
        chunk.emit(makeABC((uint8_t)Op::GET_INDEX, (uint8_t)(call_base + 1), (uint8_t)tmp, (uint8_t)key_r));
        reg_top_ = call_base + 2;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
    } else {
        // R[call_base] = receiver (self)
        compileInto(*e.receiver, call_base);
        reg_top_ = call_base + 1;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;

        // R[call_base+1] = GET_INDEX(receiver, method_name)
        int key_r = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        chunk.emit(makeABx((uint8_t)Op::LOAD_K, (uint8_t)key_r, chunk.addConstant(Value(std::string(e.method)))));
        chunk.emit(makeABC((uint8_t)Op::GET_INDEX, (uint8_t)(call_base + 1), (uint8_t)call_base, (uint8_t)key_r));
        reg_top_ = call_base + 2;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
    }

    // obj.m?() ≡ if m then m(args) else nil : JUMP_IF_FALSE saute AVANT les args
    // si la méthode (R[call_base+1]) est falsy → args non évalués.
    size_t skip = 0;
    if (e.optional)
        skip = chunk.emitJump(Op::JUMP_IF_FALSE, (uint8_t)(call_base + 1));

    // R[call_base+2..argc+1] = args
    compileConsecutive(call_base + 2, e.args);

    chunk.emit(makeABC((uint8_t)Op::CALL_METHOD, (uint8_t)call_base, 0, (uint8_t)argc));
    if (e.optional) {
        size_t end = chunk.emitJump(Op::JUMP);                                // saute par-dessus le LOAD_NIL
        chunk.patchJump(skip, (uint16_t)chunk.currentPos());                  // cible du saut : méthode nil
        chunk.emit(makeABC((uint8_t)Op::LOAD_NIL, (uint8_t)call_base, 0, 0)); // résultat nil
        chunk.patchJump(end, (uint16_t)chunk.currentPos());
    }
    last_reg_ = call_base;
}
