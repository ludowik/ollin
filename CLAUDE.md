# Ollin — Scripting Language

## Stack
- Implémentation : **C++17**
- Build : **CMake** (cross-platform)
- Cibles : Windows, Linux, macOS, iOS, Android, wasm
- Runtime : **bytecode custom + VM register-based** (instructions 32-bit format ABC/ABx/Bx)

## Architecture (pipeline strict, modules indépendants)

```
source .ol
  → Lexer     → std::vector<Token>          (token.h)
  → Parser    → Program (AST)               (ast.h)
  → Compiler  → Chunk (bytecode)            (chunk.h)
  → VM        → exécution (register-based)
```

Chaque module ne connaît que les types qu'il consomme/produit.  
Les types partagés (`token.h`, `ast.h`, `chunk.h`) n'ont aucune dépendance entre eux.

## Structure des fichiers

```
ollin/
├── CLAUDE.md
├── CMakeLists.txt
└── src/
    ├── token.h        types Token (partagé Lexer → Parser)
    ├── ast.h          nœuds AST  (partagé Parser → Compiler)
    ├── chunk.h/.cpp   bytecode   (partagé Compiler → VM)
    ├── lexer.h/.cpp
    ├── parser.h/.cpp
    ├── compiler.h/.cpp
    ├── vm.h/.cpp
    └── main.cpp       pipeline : Lexer | Parser | Compiler | VM
```

## Syntaxe

| Fichier | Propriétaire | Rôle |
|---|---|---|
| `syntax.ol` | utilisateur | source de vérité — déclare la syntaxe par l'exemple |
| `grammar.ebnf` | Claude | grammaire formelle dérivée de `syntax.ol` — à maintenir à chaque évolution |
| `test.ol` | Claude | fichier de tests libres — modifiable à volonté |
| `docs/index.html` | Claude | tutoriel HTML — à maintenir à chaque évolution du langage |
| `ollin-vscode/` | Claude | extension VS Code (colorisation) — à maintenir à chaque évolution du langage |

**Règle** : toute évolution de la syntaxe doit mettre à jour simultanément `grammar.ebnf`, `docs/index.html`, `ollin-vscode/` et `CLAUDE.md`.

## Versionning

- Branche unique : **`main`** — tout le développement se fait directement sur main
- **Committer après chaque fonctionnalité complète** (feature atomique = 1 commit)
- Pusher sur `origin/main` après chaque commit
- `git restore <fichier>` pour annuler une modification non commitée

## Commande `perf`

Quand l'utilisateur dit **"perf"**, lancer les 5 benchmarks suivants et afficher les résultats dans un tableau **langages en colonnes, benchmarks en lignes** (Ollin | Lua | Python) :

| # | Benchmark | Script Ollin | Équivalent Lua | Équivalent Python |
|---|-----------|-------------|----------------|-------------------|
| 1 | fib(35) récursif | `scripts/bench_fib.ol` | inline | inline |
| 2 | Boucle numérique 10M | `scripts/bench_loop.ol` | inline | inline |
| 3 | Création/accès map 100K | `scripts/bench_objects.ol` | inline | inline |
| 4 | Accès array 1M | `scripts/bench_array.ol` | inline | inline |
| 5 | Appels de fonctions 1M | `scripts/bench_calls.ol` | inline | inline |

Procédure :
1. Créer les scripts manquants (bench_loop, bench_array, bench_calls) pour Ollin + équivalents Lua/Python en `/tmp/`
2. Mesurer chaque benchmark (`time` ou timer interne)
3. Présenter le tableau final avec les temps en secondes

## Maintenance de CLAUDE.md

Mettre à jour ce fichier dès qu'un point important doit être mémorisé :
architecture, conventions, décisions, règles d'outillage.  
Ne pas documenter ce qui n'est pas encore implémenté.

## Format d'instruction (32-bit)

Trois formats fixes, tous sur 32 bits (Instr = uint32_t) :

| Format | Bits [31:24] | Bits [23:16] | Bits [15:8] | Bits [7:0] | Usage |
|--------|-------------|-------------|------------|-----------|-------|
| ABC    | OP          | A           | B          | C         | ops 3-adresses |
| ABx    | OP          | A           | Bx (16 bits)          || reg + index/adresse |
| Bx     | OP          | 0           | Bx (16 bits)          || saut inconditionnel |

## Opcodes VM

| Opcode        | Format | Opérandes                  | Description                                      |
|---------------|--------|----------------------------|--------------------------------------------------|
| LOAD_K        | ABx    | A=dest, Bx=const_idx       | R[A] = constants[Bx]                             |
| LOAD_NIL      | A      | A=dest                     | R[A] = nil                                       |
| MOVE          | AB     | A=dest, B=src              | R[A] = R[B]                                      |
| LOAD_GLOBAL   | ABx    | A=dest, Bx=ident_idx       | R[A] = globals[Bx]                               |
| STORE_GLOBAL  | ABx    | A=src, Bx=ident_idx        | globals[Bx] = R[A]                               |
| ADD/SUB/MUL/DIV/MOD | ABC | A=dst, B=lhs, C=rhs   | R[A] = R[B] op R[C]                              |
| NEGATE / NOT  | AB     | A=dst, B=src               | R[A] = -R[B] / !R[B]                            |
| AND / OR      | ABC    | A=dst, B=lhs, C=rhs        | R[A] = 1.0 si condition vraie sinon 0.0          |
| EQ/NEQ/GT/LT/GE/LE | ABC | A=dst, B=lhs, C=rhs  | R[A] = 1.0 si vrai sinon 0.0                     |
| JUMP          | Bx     | Bx=addr                    | ip = Bx                                          |
| JUMP_IF_FALSE | ABx    | A=cond_reg, Bx=addr        | si falsy(R[A]) → ip = Bx                        |
| CALL_FUNC     | ABC    | A=call_base, B=func_idx, C=argc | appel fonction utilisateur                   |
| RETURN        | AB     | A=first_reg, B=count       | copie R[A..A+B-1]→R[0..B-1], pop frame          |
| RETURN_V      | AB     | A=first_reg, B=n_explicit  | retourne n explicites + varargs, pop frame       |
| LOAD_VARARGS  | AB     | A=dest, B=count (0=all)    | R[A..] = varargs du frame courant               |
| CALL_PRINT    | AB     | A=first_arg, B=argc        | print(R[A..A+B-1])                               |
| CALL_PRINTF   | AB     | A=first_arg, B=argc        | printf(R[A]=fmt, R[A+1..])                       |
| CALL_ASSERT   | AB     | A=first_arg, B=argc        | assert(R[A], R[A+1]=msg optionnel)               |
| CALL_TIME     | A      | A=dest                     | R[A] = time()                                    |
| TRY           | ABx    | A=catch_reg, Bx=catch_addr | empile handler{catch_addr, catch_reg}            |
| POP_TRY       | —      |                            | dépile le handler (try body ok)                  |
| THROW         | A      | A=value_reg                | lance R[A] → restaure frame → jump handler      |
| NEW_MAP       | A      | A=dest                     | R[A] = nouvelle map vide                         |
| GET_INDEX     | ABC    | A=dst, B=map, C=key        | R[A] = R[B][R[C]]  (B=map, C=key string)        |
| SET_INDEX     | ABC    | A=map, B=key, C=val        | R[A][R[B]] = R[C]  (A=map, B=key string)        |
| MAKE_ITER     | AB     | A=dest, B=src              | R[A] = iterator(R[B])  (Map ou Array)            |
| BAND          | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] & R[C]  (entiers)                   |
| BOR           | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] \| R[C]  (entiers)                  |
| BXOR          | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] ^ R[C]  (entiers)                   |
| BNOT          | AB     | A=dst, B=src               | R[A] = ~R[B]  (entier)                          |
| BLSHIFT       | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] << (R[C] & 63)  (entiers)           |
| BRSHIFT       | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] >> (R[C] & 63)  (entiers)           |
| FOR_ITER_NEXT | ABx    | A=block_base, Bx=end_addr  | R[A]=iter; next→R[A+1]=key,R[A+2]=val; épuisé→Bx |
| LOAD_FUNC     | ABx    | A=dest, Bx=func_idx        | R[A] = T_FUNCTION (référence à funcs[Bx])        |
| CALL_DYN      | ABC    | A=arg_base, B=func_reg, C=argc | appel via valeur T_FUNCTION dans R[B]        |
| HALT          | —      |                            | arrêt                                            |

## Allocateur de registres (Compiler)

- Les paramètres de fonction occupent R[0..n_fixed-1]
- Les variables locales (pré-scannées via collectLocals) occupent R[n_fixed..locals_top-1]
- Les temporaires sont alloués au-dessus de locals_top_ et libérés après chaque statement
- `local_regs_` mappe nom → index de registre (valable dans une portée de fonction)
- `reg_count_` = max registres utilisés → stocké dans `FuncProto.reg_count`
- À l'appel de fonction, la VM resize regs[] pour loger le nouveau frame

## Boucle `for`

Trois syntaxes :

```
for i in start..end         ## range, step = 1 implicite (bornes inclusives)
for i=start,end             ## numérique, step = 1 implicite
for i=start,end,step        ## step positif ou négatif
for k,v in map_expr         ## itération sur les entrées d'une map
```

Step absent → step = 1 (condition `i <= end`).  
Step présent → condition runtime `(end - i) * step >= 0` (valide dans les deux sens).  
Dans une fonction : `i` = registre local, `end`/`step` = registres temporaires au-dessus de `locals_top_`.  
En portée globale : `i`, `__for_end_N`, `__for_step_N` sont des globaux.  
`break` fonctionne dans toutes les formes.

`for k,v in m` et `for v in arr` : utilisent le protocole `Iterator` — `MAKE_ITER` crée l'itérateur (MapIterator snapshot ou ArrayIterator ref), stocké dans `[block+0]`. `FOR_ITER_NEXT` appelle `next(key,val)` → `[block+1]`=key, `[block+2]`=val. 3 registres persistants + 1 temp source (libéré après MAKE_ITER).

## Type map

Syntaxe JSON-like, clés toujours des chaînes :

```
var t = {}                      ## map vide
var m = {                       ## literal multi-lignes
    "a": 1,
    b: 2,                       ## clé identifiant (sans guillemets)
}
print(m["a"])                   ## GET_INDEX via crochet
print(m.a)                      ## GET_INDEX via point (syntaxe équivalente)
m["c"] = 3                      ## SET_INDEX via crochet
m.c = 3                         ## SET_INDEX via point
m["a"] += 10                    ## compound : GET_INDEX + op + SET_INDEX
m.a += 10                       ## idem via point
```

Implémentation : `Map { unordered_map<Value,Value,ValueHash,ValueEqual> data; int refcount; }` — pure hashmap, ref-counted.  
Clés de tout type Value (ValueHash/ValueEqual : INTEGER(1)==FLOAT(1.0), strings par pointeur).  
Sémantique de copie : référence comptée (partage de la même map, pas clone).  
`isFalsy(map)` → toujours `false`.  
Itération via `MapIterator` (snapshot au moment du `for`) — ordre non garanti.

## Type entier natif

Les littéraux entiers (`42`, `1_000`) sont stockés comme `int64_t` (struct taguée, T_INTEGER).  
Les opérations arithmétiques et comparaisons dispatchent sur le type :  
- INT op INT → INT (ADD, SUB, MUL, MOD, comparaisons)  
- INT op FLOAT ou FLOAT op INT → FLOAT (promotion automatique)  
- DIV → toujours FLOAT  
- Overflow int64 → wrapping silencieux (comportement x86-64)  
`Value` = 16 octets (uint8_t tag + union int64_t/double/ptr).

## Représentation de Value

Struct taguée (16 octets) — remplace le NaN-boxing :

| tag        | valeur (uint8_t) | union actif | plage              |
|------------|-----------------|-------------|---------------------|
| T_NIL      | 0               | —           | —                   |
| T_INTEGER  | 1               | ival (int64_t) | ±2^63            |
| T_FLOAT    | 2               | dval (double) | IEEE 754 double   |
| T_STRING   | 3               | sptr (std::string*) | —          |
| T_MAP      | 4               | mptr (Map*) | —               |
| T_ARRAY    | 5               | aptr (Array*) | —             |
| T_ITERATOR | 6               | iptr (Iterator*) | —          |
| T_FUNCTION | 7               | ival (int64_t, = func_idx) | index dans chunk.funcs |

