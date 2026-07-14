#pragma once
#include "chunk.h"
#include <cstdint>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <unordered_map>
#include <vector>

std::string valueToString(const Value& v);

// Mémoire tas en cours d'usage (octets), multi-plateforme. Base de la builtin mem()
// et de l'overlay mémoire du moteur graphique.
uint64_t ollinHeapBytes();

class VM {
  public:
    void execute(Chunk chunk);
    std::string invokeStr(Value v);
    static VM* current();                   // returns s_current_vm
    Value callValue(const Value& fn);                       // appelle une fonction Ollin (0 arg)
    Value callValue(const Value& fn, const Value& arg);     // appelle une fonction Ollin (1 arg)
    Value callValue(const Value& fn, const Value& a, const Value& b); // 2 args
    Value getGlobal(const std::string& name) const; // returns nil if not found
    void setGlobal(const std::string& name, const Value& value);
    // Après execute() : appelle setup() une fois, puis lance la boucle graphique via
    // graphics.run(draw) si un draw() est défini. Partagé par les points d'entrée
    // natif et WASM (une seule version gardée : graphics peut être nil/non-map).
    void runEntryHooks();

  private:
    int errLine() const;             // extracted from the lambda in execute()
    void runGoto(size_t stop_depth); // unified computed-goto dispatch loop
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
        int varargs_base = 0; // = reg_base + fp.reg_count (where varargs live in regs)
        int n_varargs = 0;    // count of extra variadic args (0 if none)
        bool is_ctor = false; // true = frame is a constructor; RETURN overrides R[0] with instance
        int return_dest = -1; // >= 0: RETURN stores R[0] into regs[return_dest] (metamethod result)
        bool negate_result = false; // true: RETURN nie (logique) le résultat avant return_dest
                                    // (utilisé par <> via __eq, et par >/>=/</<= côté « inverse »)
        std::unique_ptr<std::vector<Upvalue*>> upvals;
        std::unique_ptr<std::vector<Upvalue*>> open_upvals;
    };

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

    static Value protoChainGet(const Value& obj, const Value& key);

    static bool isInstance(const Value& v);

    uint32_t tryMetaBinary(const Value& name, int dest, Value lhs, Value rhs, bool negate = false);
    // Instancie `cls` : instance en regs[base_reg], args en regs[base_reg+arg_off+i].
    // done=true si aucun frame poussé (init absent/builtin, résultat déjà écrit) ;
    // sinon retourne l'adresse du corps de init (frame constructeur poussé).
    uint32_t instantiateClass(int base_reg, int arg_off, int argc, Value cls, bool& done);
    uint32_t tryMetaUnary(const Value& name, int dest, Value lhs);
    void closeUpvals();           // closes & frees all open upvalues of the top frame
    // Déroule la pile jusqu'au handler `h`, remet regs à sa taille, écrit la valeur
    // capturée dans le registre de catch et positionne `ip` sur le corps du catch.
    // Partagé par op_THROW (throw utilisateur) et le catch(runtime_error) C++.
    void unwindToHandler(const Handler& h, Value thrown);
    void growRegs(size_t needed); // croît par doublement, max 4096, jamais rétrécit

    // Pousse un frame d'appel, remplit les défauts et varargs, retourne fp.addr.
    uint32_t pushCallFrame(int new_base, uint8_t fi, int argc, std::unique_ptr<std::vector<Upvalue*>> fuv,
                           uint32_t return_ip, bool is_ctor = false, int return_dest = -1);

    [[gnu::always_inline]] inline double asDouble(const Value& v) {
        if (v.isInteger())
            return (double)v.asInt();
        if (v.isFloat())
            return v.asFloat();
        if (v.isNil())
            throw std::runtime_error("runtime: expected number, got nil");
        throw std::runtime_error("runtime: expected number, got string");
    }
};
