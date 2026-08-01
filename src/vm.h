#pragma once
#include "chunk.h"
#include <cstdint>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <unordered_map>
#include <vector>

std::string value_to_string(const Value& v);

// Mémoire tas en cours d'usage (octets), multi-plateforme. Base de la builtin mem()
// et de l'overlay mémoire du moteur graphique.
uint64_t ollin_heap_bytes();

class VM {
  public:
    void execute(Chunk chunk);
    std::string invoke_str(Value v);
    static VM* current();                   // returns s_current_vm
    Value call_value(const Value& fn, const Value* args, int argc); // générique
    Value call_value(const Value& fn);
    Value call_value(const Value& fn, const Value& a);
    Value call_value(const Value& fn, const Value& a, const Value& b);
    Value call_value(const Value& fn, const Value& a, const Value& b, const Value& c, const Value& d);
    // Comme callValue mais récupère jusqu'à out_cap valeurs de retour (multi-retour
    // natif→Ollin) ; renvoie le nombre effectivement écrit dans out.
    int call_value_multi(const Value& fn, const Value* args, int argc, Value* out, int out_cap);
    Value get_global(const std::string& name) const; // returns nil if not found
    void set_global(const std::string& name, const Value& value);
    // Après execute() : appelle setup() une fois, puis lance la boucle graphique via
    // graphics.run(draw) si un draw() est défini. Partagé par les points d'entrée
    // natif et WASM (une seule version gardée : graphics peut être nil/non-map).
    void run_entry_hooks();

    // Marqueur « graphics.canvas() a été appelé pour ce programme » (VM neuf par run).
    // Permet à runEntryHooks de créer un canvas IMPLICITE (à W×H) si un draw() existe
    // mais qu'aucun canvas n'a été créé explicitement. Posé par gfx_canvas.
    void mark_gfx_canvas() { gfx_canvas_created_ = true; }
    bool gfx_canvas_created() const { return gfx_canvas_created_; }

  private:
    bool gfx_canvas_created_ = false;
    std::string err_line() const;      // "file:line" from current ip
    void run_goto(size_t stop_depth); // unified computed-goto dispatch loop
    struct Handler {
        uint32_t catch_addr;
        uint8_t catch_reg;
        int reg_base;
        size_t regs_size;
        size_t call_depth;
    };

    struct Frame {
        uint32_t return_ip = 0;
        int reg_base = 0;
        int result_base = 0;  // où RETURN/RETURN_V écrit les résultats (= reg_base sauf CALL_VARARGS,
                              // qui exécute dans une zone fraîche mais renvoie au registre statique appelant)
        int varargs_base = 0; // = reg_base + fp.reg_count (where varargs live in regs)
        int n_varargs = 0;    // count of extra variadic args (0 if none)
        bool is_ctor = false; // true = frame is a constructor; RETURN overrides R[0] with instance
        int return_dest = -1; // >= 0: RETURN stores R[0] into regs[return_dest] (metamethod result)
        bool negate_result = false; // true: RETURN nie (logique) le résultat avant return_dest
                                    // (utilisé par <> via __eq, et par >/>=/</<= côté « inverse »)
        std::unique_ptr<std::vector<Upvalue*>> upvals;
        std::unique_ptr<std::vector<Upvalue*>> open_upvals;
    };

    // Inline cache monomorphe pour GET_INDEX sur une map non-instance (modules,
    // maps data). Indexé par position d'instruction. Hit = même map (mptr) + même
    // version (invalidée à chaque mutation, cf. Map::version/g_map_epoch) + même clé
    // internée → renvoie la valeur résolue sans proto_chain_get.
    struct GetIndexCache {
        const Map* map = nullptr;
        uint64_t version = 0;
        const InternedStr* key = nullptr;
        Value val;
    };
    std::vector<GetIndexCache> gicache_;

    Chunk owned_chunk;
    const Chunk* ch = nullptr;
    Value string_module_;
    uint32_t ip = 0;
    std::vector<Value> globals;
    std::vector<bool> globals_init;
    std::vector<Value> regs;
    std::vector<Frame> call_stack;
    std::vector<Handler> handler_stack;
    // Nombre de valeurs produites par le dernier appel/retour. Consommé
    // UNIQUEMENT par SPREAD_RESULTS (émis juste après un appel en destructuration
    // multi-retour) pour mettre à nil les cibles au-delà de ce que l'appel a
    // réellement renvoyé (sinon elles liraient des registres périmés).
    int last_results_ = 1;

    static Value proto_chain_get(const Value& obj, const Value& key);

    // Suite de la chaîne de prototypes (__class__ d'une map, __parent__ d'une classe),
    // la data PROPRE de obj ayant déjà été consultée par l'appelant → évite un second
    // lookup de la même clé dans obj (cf. op_GET_INDEX).
    static Value proto_chain_rest(const Value& obj, const Value& key);

    static bool is_instance(const Value& v);

    uint32_t try_meta_binary(const Value& name, int dest, Value lhs, Value rhs, bool negate = false);
    // Instancie `cls` : instance en regs[base_reg], args en regs[base_reg+arg_off+i].
    // done=true si aucun frame poussé (init absent/builtin, résultat déjà écrit) ;
    // sinon retourne l'adresse du corps de init (frame constructeur poussé).
    uint32_t instantiate_class(int base_reg, int arg_off, int argc, Value cls, bool& done);
    uint32_t try_meta_unary(const Value& name, int dest, Value lhs);
    void close_upvals();           // closes & frees all open upvalues of the top frame
    // Déroule la pile jusqu'au handler `h`, remet regs à sa taille, écrit la valeur
    // capturée dans le registre de catch et positionne `ip` sur le corps du catch.
    // Partagé par op_THROW (throw utilisateur) et le catch(runtime_error) C++.
    void unwind_to_handler(const Handler& h, Value thrown);
    void grow_regs(size_t needed); // croît par doublement, max 4096, jamais rétrécit

    // Invoque un builtin : construit le CallCtx, appelle, met à jour last_results_,
    // renvoie le nombre de valeurs produites. Point d'entrée UNIQUE des 6 sites
    // d'appel builtin → le calcul de result_cap n'est écrit qu'ici (impossible à
    // oublier/se tromper à un futur site). `results` = slots résultat (= args), `cap`
    // = nombre de slots sûrs.
    int invoke_builtin(Value::BuiltinFn fn, Value* results, int argc, int cap);
    // Variante registres : les résultats vont dans regs[result_base..] et `cap` est
    // dérivé du frame courant (varargs_base - result_base) — le calcul piégeux,
    // centralisé ici. Utilisée par CALL_DYN et CALL_METHOD.
    int invoke_builtin_regs(Value::BuiltinFn fn, int result_base, int argc);

    // Pousse un frame d'appel, remplit les défauts et varargs, retourne fp.addr.
    uint32_t push_call_frame(int new_base, uint8_t fi, int argc, std::unique_ptr<std::vector<Upvalue*>> fuv,
                           uint32_t return_ip, bool is_ctor = false, int return_dest = -1, int result_base = -1);

    [[gnu::always_inline]] inline double as_double(const Value& v) {
        if (v.is_integer())
            return (double)v.as_int();
        if (v.is_float())
            return v.as_float();
        if (v.is_nil())
            throw std::runtime_error("runtime: expected number, got nil");
        throw std::runtime_error("runtime: expected number, got string");
    }
};
