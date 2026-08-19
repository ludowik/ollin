#pragma once
#include "string_table.h"
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

// static_cast<int64_t>(d) n'est DÉFINI que si la partie entière de d tient dans
// int64 (sinon UB, et trap sur WASM). Piège : (double)INT64_MAX arrondit à 2^63,
// qui n'est PAS un int64 valide → borne haute STRICTE. INT64_MIN = -2^63 est exact,
// et -lo == 2^63. Source de vérité unique : numValue, ValueHash (clés float) et
// RangeIterator s'appuient tous dessus (évite le littéral 2^63 dupliqué).
inline bool double_fits_int64(double d) {
    constexpr double lo = static_cast<double>(std::numeric_limits<int64_t>::min()); // -2^63 (exact)
    return d >= lo && d < -lo;                                                      // -lo == 2^63, exclu
}

// Tagged union Value — 16 octets : tag(1) + _pad(3) + str_hash(4) + union(8).
//
//   NIL     : tag == T_NIL
//   Integer : tag == T_INTEGER  → int64_t  (range ±2^63)
//   Float   : tag == T_FLOAT    → double IEEE 754
//   String  : tag == T_STRING   → InternedStr*  (ref-counted, str_hash = sptr->hash)
//   Map     : tag == T_MAP      → Map*     (heap, ref-counted, clés Value)
//   Array   : tag == T_ARRAY    → Array*   (heap, ref-counted, 1-based)
//   Range   : tag == T_RANGE    → Range*   (heap, ref-counted)
//   Iterator: tag == T_ITERATOR → Iterator* (heap, ref-counted)
//   Function: tag == T_FUNCTION → func_idx (int64_t ival, index dans chunk.funcs)

struct Map;
struct Array;
struct Range;
struct Iterator;
struct Closure;
struct Value;
class VM;
// Contexte d'appel d'un builtin. Modèle Lua : le builtin écrit ses valeurs de
// retour dans les slots résultat (args[0..], qui sont les registres à partir du
// call_base) et retourne leur nombre. `result_cap` = nombre de slots sûrs
// (= reg_count du frame - A) ; toute écriture est bornée à cette capacité, ce
// qui interdit tout débordement hors du frame (cf. invariant registre).
struct CallCtx {
    VM*    vm;
    Value* args;
    int    argc;
    int    result_cap = 0;

    // Retour simple d'une valeur (migration mécanique de `return v;`).
    int ret(const Value& v);
    // Écrit la i-ème valeur de retour (bornée par result_cap). Suivi de `return n;`.
    void set_result(int i, const Value& v);
};

struct Value {
    uint8_t tag;
    uint8_t _pad[3];   // padding explicite (anciennement implicite)
    uint32_t str_hash; // hash contenu mis en cache, valide uniquement pour T_STRING
    union {
        int64_t ival;
        double dval;
        InternedStr* sptr; // pointe vers l'objet interné (refcount géré inline)
        Map* mptr;
        Array* aptr;
        Iterator* iptr;
        Closure* cptr;
        Range* rptr;
    };

    // Ordre des tags = INVARIANT de perf : tous les types NON ref-comptés
    // d'abord (0..4), puis le pivot T_STRING et tous les types ref-comptés
    // contigus (5..11). Ainsi `tag < T_STRING` sépare en UN test les valeurs
    // sans gestion mémoire (nil/int/float/function/builtin) de celles à
    // retain/release. Tout nouveau type ref-compté doit être ajouté APRÈS le
    // pivot ; tout type non compté AVANT.
    static constexpr uint8_t T_NIL = 0; // ── non ref-comptés (POD / valeur) ──
    static constexpr uint8_t T_INTEGER = 1;
    static constexpr uint8_t T_FLOAT = 2;
    static constexpr uint8_t T_FUNCTION = 3; // func_idx dans ival (pas de tas)
    static constexpr uint8_t T_BUILTIN = 4;  // pointeur de fonction natif dans ival
    static constexpr uint8_t T_BOOL = 5;     // true/false dans ival (0/1) — type ÉTANCHE, ≠ entier
    static constexpr uint8_t T_STRING = 6;   // ── pivot : ref-comptés à partir d'ici ──
    static constexpr uint8_t T_MAP = 7;
    static constexpr uint8_t T_ARRAY = 8;
    static constexpr uint8_t T_ITERATOR = 9;
    static constexpr uint8_t T_CLOSURE = 10;
    static constexpr uint8_t T_CLASS = 11;  // prototype de classe (Map* réutilisé)
    static constexpr uint8_t T_RANGE = 12;  // range [a;b] (Range*, ref-counted)

  private:
    explicit Value(Map* p) : tag(T_MAP), str_hash(0), mptr(p) {
    }
    explicit Value(Array* p) : tag(T_ARRAY), str_hash(0), aptr(p) {
    }
    explicit Value(Iterator* p) : tag(T_ITERATOR), str_hash(0), iptr(p) {
    }
    explicit Value(Closure* p) : tag(T_CLOSURE), str_hash(0), cptr(p) {
    }
    explicit Value(Range* p) : tag(T_RANGE), str_hash(0), rptr(p) {
    }
    // Construction DIRECTE d'un booléen (liste d'initialisation, pas d'écriture après coup) :
    // les comparaisons en produisent un par test, sur le chemin le plus chaud de la VM.
    // Le tag-type évite de heurter Value(int64_t).
    struct BoolTag {};
    Value(BoolTag, bool b) : tag(T_BOOL), str_hash(0), ival(b ? 1 : 0) {
    }
    void release() noexcept;
    void release_cold() noexcept; // chemin froid (types ref-comptés) — non inliné
    void retain() const noexcept;

  public:
    Value() : tag(T_NIL), str_hash(0), ival(0) {
    }
    Value(double d) : tag(T_FLOAT), str_hash(0), dval(d) {
    }
    Value(int64_t v) : tag(T_INTEGER), str_hash(0), ival(v) {
    }
    Value(std::string v) : tag(T_STRING), str_hash(0) {
        sptr = intern(std::move(v));
        str_hash = sptr->hash;
    }

    Value(const Value& o);
    Value(Value&& o) noexcept : tag(o.tag), str_hash(o.str_hash), ival(o.ival) {
        o.tag = T_NIL;
    }
    Value& operator=(const Value& o);
    Value& operator=(Value&& o) noexcept;
    ~Value();

    bool is_nil() const {
        return tag == T_NIL;
    }
    bool is_float() const {
        return tag == T_FLOAT;
    }
    bool is_integer() const {
        return tag == T_INTEGER;
    }
    bool is_bool() const {
        return tag == T_BOOL;
    }
    bool as_bool() const {
        return ival != 0;
    }
    bool is_number() const {
        return tag == T_INTEGER || tag == T_FLOAT;
    }
    bool is_string() const {
        return tag == T_STRING;
    }
    bool is_map() const {
        return tag == T_MAP;
    }
    bool is_array() const {
        return tag == T_ARRAY;
    }
    bool is_iterator() const {
        return tag == T_ITERATOR;
    }
    bool is_func_val() const {
        return tag == T_FUNCTION;
    }
    bool is_closure() const {
        return tag == T_CLOSURE;
    }
    bool is_builtin() const {
        return tag == T_BUILTIN;
    }
    bool is_class() const {
        return tag == T_CLASS;
    }
    bool is_range() const {
        return tag == T_RANGE;
    }
    bool is_callable() const {
        return tag == T_FUNCTION || tag == T_CLOSURE || tag == T_BUILTIN || tag == T_CLASS;
    }

    Closure* as_closure() const {
        return cptr;
    }
    Map* as_map() const {
        return mptr;
    }

    using BuiltinFn = int (*)(CallCtx&);
    BuiltinFn as_builtin() const {
        return (BuiltinFn)(intptr_t)ival;
    }

    static Value make_func(uint8_t idx) {
        Value v;
        v.tag = T_FUNCTION;
        v.ival = idx;
        return v;
    }
    static Value make_closure(Closure* p) {
        return Value(p);
    }
    // Fabrique EXPLICITE, et non un constructeur `Value(bool)` : avec `Value(int64_t)` et
    // `Value(double)` déjà présents, un tel constructeur ferait de `Value(0)` un booléen par
    // conversion implicite silencieuse.
    static Value make_bool(bool b) {
        return Value(BoolTag{}, b);
    }
    static Value make_builtin(BuiltinFn fn) {
        Value v;
        v.tag = T_BUILTIN;
        v.ival = (int64_t)(intptr_t)fn;
        return v;
    }
    // Builtin déclaré STATIQUE (méthode de classe) : CALL_METHOD ne lui injecte pas
    // self, comme un `static func` Ollin → mêmes règles pour les classes Ollin et
    // builtin (arguments explicites en R[0..], sans receveur devant). Le marqueur est
    // porté par str_hash (inutilisé pour T_BUILTIN, mais préservé à la copie — pas _pad).
    static Value make_static_builtin(BuiltinFn fn) {
        Value v = make_builtin(fn);
        v.str_hash = 1;
        return v;
    }
    bool is_static_builtin() const {
        return tag == T_BUILTIN && str_hash != 0;
    }
    static Value make_class();
    static Value make_range(Range* r) {
        return Value(r);
    }

    int64_t as_int() const {
        return ival;
    }
    double as_float() const {
        return dval;
    }
    double as_num() const {
        return is_integer() ? (double)ival : dval;
    }
    const std::string& as_string() const {
        return sptr->str;
    }

    static Value make_map();
    Value map_get(const Value& key) const;
    void map_set(const Value& key, const Value& val);

    static Value make_array();
    Value array_get(int64_t idx) const;            // 1-based
    void array_set(int64_t idx, const Value& val); // 1-based, grows if needed
    void array_push(const Value& val);
    Value array_pop();
    void array_insert(int64_t idx, const Value& val);
    Value array_remove(int64_t idx);
    Value array_shift();
    int64_t array_size() const;
    int64_t map_size() const;

    static Value make_iter_from(const Value& src);

    const char* type_name() const {
        switch (tag) {
        case T_NIL:
            return "nil";
        case T_INTEGER:
            return "int";
        case T_FLOAT:
            return "float";
        case T_BOOL:
            return "bool";
        case T_STRING:
            return "string";
        case T_MAP:
            return "map";
        case T_ARRAY:
            return "array";
        case T_ITERATOR:
            return "iterator";
        case T_FUNCTION:
            return "function";
        case T_CLOSURE:
            return "function";
        case T_BUILTIN:
            return "function";
        case T_CLASS:
            return "class";
        case T_RANGE:
            return "range";
        default:
            return "unknown";
        }
    }
};

inline int CallCtx::ret(const Value& v) {
    if (result_cap <= 0)
        return 0;
    args[0] = v;
    return 1;
}

inline void CallCtx::set_result(int i, const Value& v) {
    if (i >= 0 && i < result_cap)
        args[i] = v;
}

// ── Array (1-based, ref-counted) — définition complète ───────────────────────
#include "collections/array.h"

// ── Map (pure hashmap, clés Value) — définition complète ─────────────────────
#include "collections/map.h"

// ── Iterator (protocole d'itération — Map, Array) ────────────────────────────
#include "collections/iterator.h"

// ── Range ([a;b] littéral, itérable) ─────────────────────────────────────────
#include "collections/range.h"

// ── Closure / Upvalue ─────────────────────────────────────────────────────────
#include "closure.h"

// ── inline Value implementations (nécessitent Map, Array, Iterator complets) ─

inline Value Value::make_map() {
    return Value(map_pool().acquire());
}
inline Value Value::make_array() {
    return Value(array_pool().acquire());
}
inline Value Value::make_class() {
    Value v;
    v.tag = T_CLASS;
    v.mptr = map_pool().acquire();
    return v;
}

inline Value Value::map_get(const Value& k) const {
    return mptr->get(k);
}
inline void Value::map_set(const Value& k, const Value& v) {
    mptr->set(k, v);
}

inline Value Value::array_get(int64_t idx) const {
    return aptr->get(idx);
}
inline void Value::array_set(int64_t idx, const Value& v) {
    aptr->set(idx, v);
}
inline void Value::array_push(const Value& v) {
    aptr->push(v);
}
inline Value Value::array_pop() {
    return aptr->pop();
}
inline void Value::array_insert(int64_t idx, const Value& v) {
    aptr->insert_at(idx, v);
}
inline Value Value::array_remove(int64_t idx) {
    return aptr->remove_at(idx);
}
inline Value Value::array_shift() {
    return aptr->shift();
}
inline int64_t Value::array_size() const {
    return (int64_t)aptr->items.size();
}
inline int64_t Value::map_size() const {
    return (int64_t)mptr->data.size();
}

// Chemin chaud : pour nil/int/float (tag < T_STRING) il n'y a rien à libérer.
// On garde ce test trivial inlinable à chaque site d'appel et on déporte le
// switch ref-compté dans release_cold() (non inliné) → move-assign s'inline.
inline void Value::release() noexcept {
    if (tag < T_STRING)
        return; // POD : rien à libérer (un seul test, inliné)
    release_cold();
}

__attribute__((noinline)) inline void Value::release_cold() noexcept {
    switch (tag) {
    case T_STRING:
        if (--sptr->refcount == 0)
            string_table().erase(sptr);
        break;
    case T_MAP:
    case T_CLASS: {
        Map* mp = mptr;
        if (--mp->refcount == 0)
            map_pool().release(mp);
        break;
    }
    case T_ARRAY: {
        Array* ap = aptr;
        if (--ap->refcount == 0)
            array_pool().release(ap);
        break;
    }
    case T_ITERATOR: {
        Iterator* ip = iptr;
        if (--ip->refcount == 0)
            ip->release();
        break;
    }
    case T_CLOSURE: {
        Closure* cp = cptr;
        if (--cp->refcount == 0)
            delete cp;
        break;
    }
    case T_RANGE: {
        Range* rp = rptr;
        if (--rp->refcount == 0)
            delete rp;
        break;
    }
    default:
        break; // défensif : seuls les tags >= T_STRING arrivent ici
    }
}

// Symétrique de release() : incrémente le refcount du type ref-compté pointé.
// Corps trivial (++refcount) → reste inlinable AVEC le switch (pas besoin de la
// découpe cold de release, dont les corps sont lourds). Grâce au pivot, les
// types non comptés (dont T_FUNCTION/T_BUILTIN) sortent dès `tag < T_STRING`.
inline void Value::retain() const noexcept {
    if (tag < T_STRING)
        return; // POD / non comptés : rien à retenir (un seul test)
    switch (tag) {
    case T_STRING:
        ++sptr->refcount;
        break;
    case T_MAP:
    case T_CLASS:
        mptr->refcount++;
        break;
    case T_ARRAY:
        aptr->refcount++;
        break;
    case T_ITERATOR:
        iptr->refcount++;
        break;
    case T_CLOSURE:
        cptr->refcount++;
        break;
    case T_RANGE:
        rptr->refcount++;
        break;
    default:
        break; // défensif : seuls les tags >= T_STRING arrivent ici
    }
}

inline Value Value::make_iter_from(const Value& src) {
    if (src.is_map() || src.is_class())
        return Value(new MapIterator(src.mptr));
    if (src.is_array())
        return Value(array_iter_pool().acquire(src.aptr));
    if (src.is_range())
        return Value(new RangeIterator(src.rptr));
    throw std::runtime_error("runtime: for-in on non-iterable");
}

inline Value::Value(const Value& o) : tag(o.tag), str_hash(o.str_hash), ival(o.ival) {
    // copie brute de l'union (ival/dval/ptr aliasent les 8 mêmes octets) ; seul
    // un type ref-compté (tag >= T_STRING) demande un retain.
    retain();
}
inline Value& Value::operator=(const Value& o) {
    if (this == &o)
        return *this;
    o.retain(); // retain d'abord (protège si this et o partagent la même ressource)
    release();
    // copie brute de l'union (ival/dval/ptr aliasent les 8 mêmes octets)
    tag = o.tag;
    str_hash = o.str_hash;
    ival = o.ival;
    return *this;
}
inline Value& Value::operator=(Value&& o) noexcept {
    if (this == &o)
        return *this;
    release();
    tag = o.tag;
    str_hash = o.str_hash;
    ival = o.ival;
    o.tag = T_NIL;
    return *this;
}
inline Value::~Value() {
    release();
}

// Vérité des types dont la réponse demande un ACCÈS MÉMOIRE (longueur d'une chaîne, taille
// d'un tableau ou d'une map). `noinline` l'empêche de grossir ses appelants : is_falsy est
// inlinée sur une quinzaine de sites, dont JUMP_IF_FALSE, le plus chaud de la VM — chaque
// test qu'on lui retire allège tout ce code.
//
// PAS de `gnu::cold` ici, mesuré : l'attribut marque aussi les APPELANTS comme improbables,
// et run_goto les contient tous — la boucle numérique y perdait 33 % (bench_loop), pour un
// compte d'instructions inchangé. Un attribut qui déclare un chemin froid dégrade donc la
// fonction géante qui héberge tous les chemins chauds.
[[gnu::noinline]] inline bool is_falsy_cold(const Value& v) {
    if (v.is_float())
        return v.as_float() == 0.0;
    if (v.is_string())
        return v.as_string().empty();
    if (v.is_array())
        return v.array_size() == 0;
    if (v.is_map())
        return v.map_size() == 0; // instance : ≥1 clé (__class__) → truthy
    return false;                // T_CLASS, range, closure, function → truthy
}

inline bool is_falsy(const Value& v) {
    // principe : « le vide est faux » — un booléen répond pour lui-même, tout le reste
    // garde ses règles (0, chaîne vide, tableau vide et map vide sont faux).
    // Ne restent inlinés que les trois tags qui répondent SANS toucher la mémoire, dans
    // l'ordre de leur fréquence sur ce chemin : le booléen d'abord, les comparaisons en
    // produisant un par test.
    if (v.is_bool())
        return !v.as_bool();
    if (v.is_integer())
        return v.as_int() == 0;
    if (v.is_nil())
        return true;
    return is_falsy_cold(v);
}

inline Value num_value(double d) {
    // Repli en entier si d est un entier exact représentable en int64. doubleFitsInt64
    // garde le cast (UB sur NaN/inf/hors plage) ; le round-trip vérifie l'exactitude.
    if (double_fits_int64(d)) {
        int64_t i = static_cast<int64_t>(d);
        if (static_cast<double>(i) == d)
            return Value(i);
    }
    return Value(d);
}
