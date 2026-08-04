#pragma once
#include "ast.h"
#include "chunk.h"
#include <functional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class Compiler : public StmtVisitor, public ExprVisitor {
  public:
    Chunk compile(const Program& program);

  private:
    Chunk chunk;
    std::vector<std::vector<size_t>> break_patches;
    std::vector<std::vector<size_t>> continue_patches;
    int current_line_ = 0;
    int current_file_idx_ = 0;

    // ── register allocator ────────────────────────────────────────────────────
    std::unordered_map<std::string, int> local_regs_;
    // Locales `var`/`const` dont le registre est réservé mais qui ne sont PAS encore
    // déclarées (portée lexicale : visibles seulement à partir de leur ligne). Une
    // référence avant la déclaration ne les trouve donc pas dans local_regs_ → tombe
    // sur global/upvalue/erreur. Activées (déplacées vers local_regs_) au VarDeclStmt.
    // Sauvée/restaurée partout où local_regs_ l'est (portées imbriquées).
    std::unordered_map<std::string, int> pending_var_reg_;
    int reg_top_ = 0;    // next free register
    int reg_count_ = 0;  // max reg ever used → FuncProto.reg_count
    int locals_top_ = 0; // reg_top_ after pre-scanning locals (temps start here)
    int last_reg_ = -1;  // result register of last compiled expression

    // ── function scope ────────────────────────────────────────────────────────
    struct FuncInfo {
        uint8_t func_idx;
        int n_fixed;
        bool variadic;
        bool is_closure = false; // true = has upvalues, called via LOAD_GLOBAL+CALL_DYN
    };
    std::unordered_map<std::string, FuncInfo> func_table;
    std::unordered_set<std::string> declared_globals_; // globals déclarés (source + builtins + modules)
    std::unordered_set<std::string> const_names_;      // locals declared with 'const'
    // Enums déclarés sous un nom simple → refus des écritures visibles dès la
    // compilation (message nommant l'élément). La VM garde tous les autres chemins.
    std::unordered_set<std::string> enum_names_;
    std::string current_func_name;                     // "" = global scope
    // Nom de la classe parente de la classe dont on compile actuellement une
    // méthode ("" hors classe / classe sans parent). 'super' se résout par CETTE
    // classe lexicale, pas par la classe dynamique de self (sinon récursion
    // infinie dans une hiérarchie à 3+ niveaux).
    std::string current_class_parent_;
    int current_func_idx_ = -1;                        // index in chunk.funcs (-1 = main chunk)

    bool in_function() const {
        return !current_func_name.empty();
    }

    // ── upvalue resolution ────────────────────────────────────────────────────
    struct OuterScope {
        std::unordered_map<std::string, int> regs;
        std::unordered_map<std::string, int> upval_idx; // name → upvalue index in this scope's proto
        std::unordered_set<std::string> consts;         // constants declared in this scope
        int func_proto_idx;                             // -1 = main chunk
    };
    std::vector<OuterScope> outer_scopes_;
    std::unordered_map<std::string, int> cur_upval_idx_;

    int resolve_upvalue(const std::string& name);
    int resolve_upval_from(int scope_idx, const std::string& name);
    int capture_upval_chain(int scope_idx, bool is_local, uint8_t idx, const std::string& name);
    uint8_t compile_method_func(const FuncDeclStmt& s);
    void compile_iterator_loop(const Expr& src, const std::string& var1, const std::string& var2,
                             const std::vector<std::unique_ptr<Stmt>>& body);
    // chemin rapide for numérique (range littéral inclus aux 2 bornes, 1 variable)
    void compile_numeric_for(const RangeExpr& r, const std::string& var1, const std::vector<std::unique_ptr<Stmt>>& body);

    int alloc_reg() {
        int r = reg_top_++;
        if (reg_top_ > reg_count_)
            reg_count_ = reg_top_;
        return r;
    }

    // Enregistre la ligne source courante (pour les diagnostics runtime) — remplace
    // le prologue `if (line > 0) { current_line_ = line; chunk.setLine(line); }`
    // dupliqué dans chaque visit().
    void note_line(int line, int fi = -1) {
        if (line > 0) {
            current_line_ = line;
            if (fi >= 0)
                current_file_idx_ = fi;
            chunk.set_line(line, current_file_idx_);
        }
    }

    SourceLoc sloc() const { return {(uint16_t)current_file_idx_, (uint16_t)current_line_}; }

    void compile_into(const Expr& e, int dest);
    void compile_consecutive(int base, const std::vector<std::unique_ptr<Expr>>& exprs);
    // Portée lexicale stricte : sauvegarde local_regs_/reg_top_/locals_top_, alloue
    // les locales déclarées dans body (sans descendre dans les sous-blocs), compile,
    // puis restaure. Les registres restent réservés si le corps contient des closures.
    void compile_block(const std::vector<std::unique_ptr<Stmt>>& body);

    // Réserve un registre pour chaque locale pré-scannée. Les fonctions (funcs) sont
    // liées d'emblée dans local_regs_ (récursion / références en avant) ; les var/const
    // sont différées dans pending_var_reg_ (portée lexicale). `skip` = noms du prologue
    // de la portée COURANTE (params, self, catch var) : laissés tels quels. Un nom hérité
    // d'une portée englobante n'est PAS dans skip → il obtient un registre neuf (masquage).
    void bind_scan_locals(const std::vector<std::string>& names, const std::unordered_set<std::string>& funcs,
                        const std::unordered_set<std::string>& skip = {});

    // Charge la valeur appelable nommée `name` dans le registre `reg` (locale, upvalue,
    // fonction top-level via LOAD_FUNC, ou global via LOAD_GLOBAL).
    void emit_callee_value(const std::string& name, int reg);
    // Compile un appel dont le DERNIER argument est multi-valeurs (… ou appel) : callee
    // sous le bloc d'arguments, args fixes, puis expansion — émet CALL_VARARGS (…) ou
    // CALL_VA (appel). emitCallee(reg) place l'appelable. Résultat via last_reg_ = call_base.
    void emit_spread_call(const std::vector<std::unique_ptr<Expr>>& args,
                        const std::function<void(int)>& emit_callee);

    // StmtVisitor
    void visit(const CommentStmt&) override {
    }
    void visit(const VarDeclStmt&) override;
    void visit(const WhileStmt&) override;
    void visit(const IfStmt&) override;
    void visit(const BreakStmt&) override;
    void visit(const ContinueStmt&) override;
    void visit(const AssignStmt&) override;
    void visit(const ExprStmt&) override;
    void visit(const ThrowStmt&) override;
    void visit(const TryCatchStmt&) override;
    void visit(const FuncDeclStmt&) override;
    void visit(const ReturnStmt&) override;

    void visit(const ForIterStmt&) override;
    void visit(const BlockStmt&) override;
    void visit(const ClassDeclStmt&) override;
    void visit(const EnumDeclStmt&) override;
    void visit(const SwitchStmt&) override;
    void visit(const DoStmt&) override;

    // ExprVisitor
    void visit(const BoolExpr&) override;
    void visit(const NumberExpr&) override;
    void visit(const StringExpr&) override;
    void visit(const VarExpr&) override;
    void visit(const BinaryExpr&) override;
    void visit(const CallExpr&) override;
    void visit(const UnaryExpr&) override;
    void visit(const VarArgExpr&) override;
    void visit(const NilExpr&) override;
    void visit(const MapExpr&) override;
    void visit(const IndexExpr&) override;
    void visit(const ArrayExpr&) override;
    void visit(const ExprCallExpr&) override;
    void visit(const MethodCallExpr&) override;
    void visit(const RangeExpr&) override;
    void visit(const FuncExpr&) override;
    void visit(const ChainedCompareExpr&) override;
    void visit(const InterpExpr&) override;

    // StmtVisitor (map)
    void visit(const IndexAssignStmt&) override;
    void visit(const MultiAssignStmt&) override;
};
