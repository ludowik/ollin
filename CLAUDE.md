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

- **Git** initialisé à la racine — utiliser `git restore <fichier>` pour annuler une modification
- Committer après chaque changement significatif

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
| FOR_MAP_STEP  | ABx    | A=block_base, Bx=end_addr  | R[A+3]=map R[A+2]=iter; si iter≥size→Bx sinon R[A]=key R[A+1]=val iter++ |
| BAND          | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] & R[C]  (entiers)                   |
| BOR           | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] \| R[C]  (entiers)                  |
| BXOR          | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] ^ R[C]  (entiers)                   |
| BNOT          | AB     | A=dst, B=src               | R[A] = ~R[B]  (entier)                          |
| BLSHIFT       | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] << (R[C] & 63)  (entiers)           |
| BRSHIFT       | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] >> (R[C] & 63)  (entiers)           |
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

`for k,v in m` : utilise 4 registres contigus au-dessus de `locals_top_` : `[block+0]`=key_out, `[block+1]`=val_out, `[block+2]`=iter, `[block+3]`=map_ref. Opcode `FOR_MAP_STEP`.

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

Implémentation : `OllinMap { vector<pair<string,Value>> entries; int refcount; }`, pointeur 48-bit dans le NaN-boxing (MTAG = 0x7FFE).  
Sémantique de copie : référence comptée (partage de la même map, pas clone).  
`isFalsy(map)` → toujours `false`.

## Type entier natif

Les littéraux entiers (`42`, `1_000`) sont stockés comme `int48` dans le NaN-boxing (tag `0x7FFD_xxxx_xxxx_xxxx`).  
Les opérations arithmétiques et comparaisons dispatchent sur le type :  
- INT op INT → INT (ADD, SUB, MUL, MOD, comparaisons)  
- INT op FLOAT ou FLOAT op INT → FLOAT (promotion automatique)  
- DIV → toujours FLOAT  
- Overflow int48 → wrapping silencieux (à améliorer si besoin)  
`Value` reste 8 octets (NaN-boxing inchangé).
