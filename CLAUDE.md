# Ollin — Scripting Language
> Minimaliste · Expressif · Dynamiquement typé · Compilé · Embarquable

## Règle obligatoire : écrire du code Ollin

Avant d'écrire **tout** fichier `.ol`, lire dans cet ordre :
1. `docs/grammar.ebnf` — syntaxe formelle du langage
2. `scripts/syntax.ol` — exemples de référence

Tester ensuite avec `./build/ollin <script>` avant tout build WASM.  
Ces deux étapes sont **non négociables**, quelle que soit la taille du script.

## Stack
- Implémentation : **C++17**
- Build : **CMake** (cross-platform)
- Compilateurs supportés : **GCC et Clang** (computed-goto requis — MSVC non supporté)
- Cibles : Windows (Clang natif), Linux, macOS, iOS, Android, wasm
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
    ├── closure.h      Upvalue + Closure (inclus par chunk.h)
    ├── map.h/.cpp     Map + ValueHash/ValueEqual (inclus par chunk.h)
    ├── lexer.h/.cpp
    ├── parser.h/.cpp
    ├── compiler.h/.cpp
    ├── vm.h/.cpp
    └── main.cpp       pipeline : Lexer | Parser | Compiler | VM
```

## Syntaxe

> **La syntaxe et la sémantique du langage sont décrites dans [`docs/grammar.ebnf`](docs/grammar.ebnf).**
> CLAUDE.md ne documente **pas** la syntaxe — il décrit l'architecture et l'implémentation (opcodes, registres, structures internes). Pour toute question sur la forme du langage, lire la grammaire.

| Fichier | Propriétaire | Rôle |
|---|---|---|
| `scripts/syntax.ol` | utilisateur | source de vérité syntaxe + suite de tests complète |
| `docs/grammar.ebnf` | Claude | **grammaire formelle = référence de la syntaxe du langage** (dérivée de `syntax.ol`) |
| `docs/index.html` | Claude | tutoriel HTML |
| `ollin-vscode/` | Claude | extension VS Code (colorisation) |

**Règle** : toute évolution de la syntaxe doit mettre à jour simultanément `grammar.ebnf` (référence), `syntax.ol`, `docs/index.html` et `ollin-vscode/`. CLAUDE.md n'est mis à jour que si l'implémentation (opcodes, stratégie de compilation, structures) change.

## Versionning

- Branche unique : **`main`** — tout le développement se fait directement sur main
- **Committer après chaque fonctionnalité complète** (feature atomique = 1 commit)
- Pusher sur `origin/main` après chaque commit
- `git restore <fichier>` pour annuler une modification non commitée

## Règle computed-goto (vm.cpp)

La VM utilise le **computed-goto dispatch** (`goto *dt[op]`) pour la performance (+15-25% vs switch).  
gcc/clang sont **stricts** : toute variable avec destructeur non-trivial (`Value`, `std::vector`, `std::unique_ptr`…) doit être dans un bloc `{}` qui se ferme **avant** `NEXT()`.  
Le fallback switch MSVC a été supprimé — seuls GCC et Clang sont supportés.

**Règle** : dans chaque handler computed-goto, si des variables non-triviales sont nécessaires, les encapsuler :
```cpp
op_EXEMPLE: {
    {                          // ← bloc interne
        Value v = ...;         // destructeur non-trivial
        call_stack.push_back(...);
        fp_addr = fp.addr;
    }                          // ← v détruite ici
    ip = fp_addr;
    NEXT();                    // ← goto sans variable en portée
}
```

## Commande `perf`

Quand l'utilisateur dit **"perf"**, lancer : `bash bench/bench_all.sh`

Les scripts sont dans `bench/` (`.ol`, `.lua`, `.py` pour chaque benchmark). Le tableau affiche : **temps absolu Lua** comme référence, **coefficient multiplicateur** (xN.NN) pour Ollin et Python.

| # | Benchmark | Script |
|---|-----------|--------|
| 1 | fib(35) récursif | `bench/bench_fib.*` |
| 2 | Boucle numérique 10M | `bench/bench_loop.*` |
| 3 | Création/accès map 100K | `bench/bench_objects.*` |
| 4 | Accès array 1M | `bench/bench_array.*` |
| 5 | Appels de fonctions 1M | `bench/bench_calls.*` |

**Environnement de référence (Windows) :**
- Lua : `C:\Tools\lua\lua55.exe` (Lua 5.5) — pas de Lua 5.4 disponible, pacman/MSYS2 inutilisable (timeouts réseau)
- Python : `python` ou `python3` dans le PATH
- Build : `cmake --build build` via **PowerShell** avec **Clang natif (LLVM)** — Clang définit `__GNUC__`, le computed-goto est actif

**Règles strictes pour les comparaisons :**
- Ne pas inventer de raison pour expliquer les écarts de performance — s'en tenir aux faits mesurés.

## Maintenance de CLAUDE.md

Mettre à jour ce fichier dès qu'un point important doit être mémorisé : architecture, conventions, décisions, règles d'outillage.Ne pas documenter ce qui n'est pas encore implémenté.

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
| IDIV          | ABC    | A=dst, B=lhs, C=rhs        | R[A] = floor(R[B] / R[C])  (INT//INT → INT)      |
| POW           | ABC    | A=dst, B=base, C=exp       | R[A] = R[B] ^ R[C]  (INT^INT(≥0) → INT ; sinon FLOAT ; '^' = puissance, modèle Lua) |
| NEGATE / NOT  | AB     | A=dst, B=src               | R[A] = -R[B] / !R[B]                            |
| AND / OR      | ABC    | A=dst, B=lhs, C=rhs        | R[A] = 1.0 si condition vraie sinon 0.0          |
| EQ/NEQ/GT/LT/GE/LE | ABC | A=dst, B=lhs, C=rhs  | R[A] = 1.0 si vrai sinon 0.0                     |
| JUMP          | Bx     | Bx=addr                    | ip = Bx                                          |
| JUMP_IF_FALSE | ABx    | A=cond_reg, Bx=addr        | si falsy(R[A]) → ip = Bx (aussi : appel optionnel f?()) |
| CALL_FUNC     | ABC    | A=call_base, B=func_idx, C=argc | appel fonction utilisateur                   |
| RETURN        | AB     | A=first_reg, B=count       | copie R[A..A+B-1]→R[0..B-1], pop frame          |
| RETURN_V      | AB     | A=first_reg, B=n_explicit  | retourne n explicites + varargs, pop frame       |
| LOAD_VARARGS  | AB     | A=dest, B=count (0=all)    | R[A..] = varargs du frame courant               |
| TRY           | ABx    | A=catch_reg, Bx=catch_addr | empile handler{catch_addr, catch_reg}            |
| POP_TRY       | —      |                            | dépile le handler (try body ok)                  |
| THROW         | A      | A=value_reg                | lance R[A] → restaure frame → jump handler      |
| NEW_MAP       | A      | A=dest                     | R[A] = nouvelle map vide                         |
| GET_INDEX     | ABC    | A=dst, B=obj, C=key        | R[A] = R[B][R[C]]  (map: Value key, array: int 1-based) |
| SET_INDEX     | ABC    | A=obj, B=key, C=val        | R[A][R[B]] = R[C]  (map: Value key, array: int 1-based) |
| MAKE_ITER     | AB     | A=dest, B=src              | R[A] = iterator(R[B])  (Map ou Array)            |
| BAND          | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] & R[C]  (entiers)                   |
| BOR           | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] \| R[C]  (entiers)                  |
| BXOR          | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] ~ R[C]  (entiers ; '~' binaire = XOR, modèle Lua) |
| BNOT          | AB     | A=dst, B=src               | R[A] = ~R[B]  (entier)                          |
| BLSHIFT       | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] << (R[C] & 63)  (entiers)           |
| BRSHIFT       | ABC    | A=dst, B=lhs, C=rhs        | R[A] = R[B] >> (R[C] & 63)  (entiers)           |
| NEW_ARRAY     | A      | A=dest                     | R[A] = []  (array vide)                          |
| ARRAY_PUSH    | AB     | A=arr, B=val               | R[A].push(R[B])                                  |
| FOR_ITER_NEXT | ABx    | A=block_base, Bx=end_addr  | R[A]=iter; next→R[A+1]=key,R[A+2]=val; épuisé→Bx |
| FOR_PREP      | ABx    | A=ctl, Bx=loop_addr        | for numérique : R[A..A+2]=i,limite,pas ; valide, fige int/float, i-=pas, ip=Bx |
| FOR_LOOP      | ABx    | A=ctl, Bx=body_addr        | i+=pas ; si dans la limite → R[A]=i, ip=Bx (corps) ; sinon sortie |
| LOAD_FUNC     | ABx    | A=dest, Bx=func_idx        | R[A] = T_FUNCTION (référence à funcs[Bx])        |
| CALL_DYN      | ABC    | A=arg_base, B=func_reg, C=argc | appel via T_FUNCTION ou T_CLOSURE dans R[B]  |
| MAKE_CLOSURE  | ABx    | A=dest, Bx=func_idx        | R[A] = Closure{func_idx, capture upvals depuis frame courant} |
| GET_UPVAL     | AB     | A=dest, B=upval_idx        | R[A] = upval[B]  (ouverte: regs[base+idx], fermée: uv.val) |
| SET_UPVAL     | AB     | A=src, B=upval_idx         | upval[B] = R[A]                                  |
| NEW_CLASS     | A      | A=dest                     | R[A] = nouvelle classe vide (T_CLASS)            |
| CALL_METHOD   | ABC    | A=recv_base, B=0, C=argc   | R[A]=receiver, R[A+1]=fn, R[A+2..]=args ; self auto si instance |
| HALT          | —      |                            | arrêt                                            |

## Déclaration de variables (implémentation de l'enforcement)

> Règle de langage (`var` = locale, `global` = globale, obligation de déclaration) : voir `grammar.ebnf` (`varDecl`, `globalDecl`, `assignStmt`).

- Message d'erreur émis : `undeclared variable '<nom>' (use 'var' or 'global')`.
- `declared_globals_` (set) contient : noms de classes, et tous les noms déclarés par `global`.
- **Pré-scan** : `collectGlobals()` parcourt tout le programme (y compris l'intérieur des fonctions, classes, blocs) et remplit `declared_globals_` **avant** la compilation → les références en avant à un global fonctionnent.
- `VarDeclStmt.is_global` : `collectLocals()` ignore ces déclarations (pas de registre) ; `visit(VarDeclStmt)` émet `STORE_GLOBAL` pour l'init.
- Résolution d'un nom : local (`local_regs_`) → fonction (`func_table`) → upvalue (`resolveUpvalue`) → global (`declared_globals_` → `LOAD_GLOBAL`/`STORE_GLOBAL`) → sinon erreur. Une locale masque donc un global de même nom.
- Garde-fous + branche global dans le compilateur : `visit(AssignStmt)`, `visit(VarExpr)`, `visit(IndexAssignStmt)`.

## Allocateur de registres (Compiler)

- Les paramètres de fonction occupent R[0..n_fixed-1]
- Les variables locales (pré-scannées via collectLocals) occupent R[n_fixed..locals_top-1]
- Les temporaires sont alloués au-dessus de locals_top_ et libérés après chaque statement
- `local_regs_` mappe nom → index de registre (valable dans une portée de fonction)
- `reg_count_` = max registres utilisés → stocké dans `FuncProto.reg_count`
- À l'appel de fonction, la VM resize regs[] pour loger le nouveau frame

## Boucle `for` (implémentation)

> Syntaxe et sémantique (formes numérique/itérateur, valeur primaire, step) : voir `grammar.ebnf` (`forStmt`).

**Désucrage** : `for i = a, b[, step]` est réécrit par le parser en `for i in [a;b[;step]]` (RangeExpr inclus aux deux bornes). Il n'existe qu'un nœud AST : `ForIterStmt`.

**Chemin rapide numérique** (`compileNumericFor`) : déclenché quand `iter_expr` est un **RangeExpr littéral inclus aux deux bornes** (`incl_left && incl_right`) avec **1 variable** — couvre `for i = a, b[, step]` et `for i in [a;b]`. Pas de `Range` ni d'itérateur ni de dispatch virtuel.  
- 3 registres consécutifs `ctl/ctl+1/ctl+2` = `i / limite / pas`.  
- `FOR_PREP ctl, →FOR_LOOP` : valide (nombres, pas≠0), fige le type (tout int → int64 ; sinon tout converti en double), `i -= pas`, saute vers `FOR_LOOP`.  
- `FOR_LOOP ctl, →corps` : `i += pas` ; si dans la limite (`≤` si pas>0, `≥` sinon) → `R[ctl]=i`, saut vers le corps ; sinon sortie. `bind(var1, ctl)` copie `i` dans la variable en tête de corps (modifier la variable dans le corps n'affecte pas l'itération).  
Les ranges ouverts (`[a;b[`, `]a;b]`…) et `for k,v in …` gardent le chemin itérateur ci-dessous.

**Itérateur** (`for [k,] v in expr`) : `MAKE_ITER` crée l'itérateur (MapIterator snapshot, ArrayIterator ref, ou RangeIterator), stocké dans `[block+0]`.  
- 2 vars : `FOR_ITER_NEXT` → `[block+1]`=key, `[block+2]`=val. 3 registres + 1 temp source.  
- 1 var  : `FOR_ITER_NEXT1` → `[block+1]`=primary (val si `primary_is_val()`, sinon key). 2 registres + 1 temp source.  
`Iterator::primary_is_val()` : `ArrayIterator`=true, `RangeIterator`=true, `MapIterator`=false.

## Type range (implémentation)

> Notation d'intervalles `[a;b]` / `]a;b[` / step / first-class : voir `grammar.ebnf` (`rangeLit`).

`MAKE_RANGE` (opcode ABC) : A=dest, B=base (start=R[B], end=R[B+1], step=R[B+2] si has_step), C=flags (bit0=incl_right, bit1=has_step). L'ajustement open-left est émis par le compilateur via ADD avant MAKE_RANGE.  
`T_RANGE = 11` — Range* ref-counted avec `{start, end, step, incl_right}` (entiers uniquement).

## Type map (implémentation)

> Syntaxe littérale JSON-like, accès `m["k"]` / `m.k`, sémantique : voir `grammar.ebnf` (`mapLit`, `indexAssign`).

Implémentation : `Map { unordered_map<Value,Value,ValueHash,ValueEqual> data; int refcount; }` — pure hashmap, ref-counted.  
Clés de tout type Value (ValueHash/ValueEqual : INTEGER(1)==FLOAT(1.0), strings par pointeur).  
Sémantique de copie : référence comptée (partage de la même map, pas clone).  
`isFalsy(map)` → `mapSize() == 0` (« le vide est faux » ; une instance a ≥1 clé `__class__` → truthy). Idem `isFalsy(array)` → `arraySize() == 0`.  
Itération via `MapIterator` (snapshot au moment du `for`) — ordre non garanti.  
Opcodes : `NEW_MAP`, `GET_INDEX`, `SET_INDEX`.

## Type entier natif (implémentation)

> Règles de promotion (INT/FLOAT) et littéraux : voir `grammar.ebnf` (`additive`, `NUMBER`).

Les littéraux entiers (`42`, `1_000`) sont stockés comme `int64_t` (struct taguée, T_INTEGER).  
Les opcodes arithmétiques/comparaison dispatchent sur le tag (INT op INT → INT ; promotion FLOAT sinon ; DIV → FLOAT).  
Overflow int64 → wrapping silencieux (comportement x86-64).  
`Value` = 16 octets (tag 1 o + pad 3 o + str_hash 4 o + union 8 o).

## Représentation de Value

Struct taguée (16 octets) — layout :

```
offset 0   : uint8_t  tag
offset 1-3 : uint8_t  _pad[3]
offset 4-7 : uint32_t str_hash  (hash contenu, valide uniquement T_STRING)
offset 8-15: union { int64_t ival; double dval; InternedStr* sptr; Map* mptr; Array* aptr; Iterator* iptr; Closure* cptr; Range* rptr; }
```

| tag        | valeur (uint8_t) | union actif | plage              |
|------------|-----------------|-------------|---------------------|
| T_NIL      | 0               | —           | —                   |
| T_INTEGER  | 1               | ival (int64_t) | ±2^63            |
| T_FLOAT    | 2               | dval (double) | IEEE 754 double   |
| T_STRING   | 3               | sptr (InternedStr*) | ref-counted, str_hash = sptr->hash |
| T_MAP      | 4               | mptr (Map*) | —               |
| T_ARRAY    | 5               | aptr (Array*) | —             |
| T_ITERATOR | 6               | iptr (Iterator*) | —          |
| T_FUNCTION | 7               | ival (int64_t, = func_idx) | index dans chunk.funcs |
| T_CLOSURE  | 8               | cptr (Closure*) | ref-counted, holds func_idx + upvals |
| T_CLASS    | 10              | mptr (Map*) | classe : même layout que T_MAP, mais distincte pour CALL_DYN |
| T_RANGE    | 11              | rptr (Range*) | intervalle entier ref-counted        |

## Closures / Upvalues

Une fonction qui référence une variable de la portée englobante capture un **upvalue**.

### Structures (`closure.h`)

```cpp
struct Upvalue {
    int refcount = 1;
    bool closed  = false;   // false = ouverte (pointe dans les regs du frame parent)
    int frame_base = 0;     // base du frame parent dans regs[]
    int reg_idx    = 0;     // index dans ce frame
    Value val;              // copie une fois le frame dépilé (upvalue fermée)
};

struct Closure {
    int refcount = 1;
    uint8_t func_idx;
    std::vector<Upvalue*> upvals;
};
```

### FuncProto (`chunk.h`)

```cpp
struct UpvalDesc { bool is_local; uint8_t idx; };
// is_local=true : upval pointe dans les regs du frame direct parent (reg idx)
// is_local=false: upval repris depuis les upvals du frame parent (upval idx)
std::vector<UpvalDesc> upvals;  // dans FuncProto
```

### Frame (`vm.h`)

```cpp
std::vector<Upvalue*> upvals;       // upvals de la closure appelante (si T_CLOSURE)
std::vector<Upvalue*> open_upvals;  // upvals ouvertes créées par ce frame
```

### Cycle de vie

1. `MAKE_CLOSURE` — crée `Closure{func_idx}`, pour chaque `UpvalDesc` : si `is_local` → crée ou réutilise un `Upvalue*` pointant dans `regs[frame_base + reg_idx]`, si non local → reprend `frame.upvals[idx]`.
2. Upvalue **ouverte** : `GET_UPVAL`/`SET_UPVAL` accèdent à `regs[frame_base + reg_idx]` du frame parent via le pointeur.
3. `RETURN` / `THROW` — ferme toutes les `open_upvals` du frame : copie `regs[base+idx]` dans `uv->val`, pose `closed=true`.
4. Upvalue **fermée** : accès via `uv->val` (le frame parent n'existe plus).

### Fonctions imbriquées

- `collectLocals` pré-alloue un registre pour chaque `FuncDeclStmt` trouvé dans le corps de la fonction englobante.
- `visit(FuncDeclStmt)` : si `is_nested` (outer_name non vide) → émet `MAKE_CLOSURE` ou `LOAD_FUNC` dans ce registre local, pas de `STORE_GLOBAL`.
- Appels récursifs à une fonction interne : `resolveUpvalue(callee)` remonte la chaîne de scopes → `GET_UPVAL + CALL_DYN`.

## Système de classes (implémentation)

> Syntaxe (`class`, `extends`, `super`, méthodes, méta-méthodes) : voir `grammar.ebnf` (`classDecl`, `method`, `superCall`).

### Représentation

- Une classe est une `T_CLASS` (= `T_MAP` à tag distinct) contenant : `__name__` (string), `__parent__` (T_CLASS, optionnel), et une entrée par méthode.
- Une instance est un `T_MAP` normal avec une clé `__class__` pointant vers sa classe.
- La recherche de propriété/méthode (`GET_INDEX`, `CALL_METHOD`) remonte la chaîne `instance → __class__ → __parent__` via `protoChainGet`.

### Compilation

- `visit(ClassDeclStmt)` : émet `NEW_CLASS`, initialise les métadonnées (`__name__`, `__parent__`), puis pour chaque méthode : `compileMethodFunc` + `LOAD_FUNC`/`MAKE_CLOSURE` + `SET_INDEX`.
- `compileMethodFunc` : comme la compilation de `FuncDeclStmt` mais ajoute `local_regs_["self"] = 0`, les paramètres utilisateur commencent à R[1], `n_fixed = 1 + n_params`.
- `visit(MethodCallExpr)` : émet CALL_METHOD avec `argc` = nombre d'arguments explicites.

### Opcodes

| Opcode | Format | Description |
|--------|--------|-------------|
| NEW_CLASS | A | R[A] = nouvelle classe vide (T_CLASS) |
| CALL_METHOD | ABC | A=receiver_base, B=0, C=argc — R[A]=receiver, R[A+1]=method_fn, R[A+2..]=args |

### CALL_DYN sur T_CLASS (instanciation)

1. Crée une instance T_MAP, pose `__class__` = la classe.
2. Cherche `init` via `protoChainGet`.
3. Si trouvé : décale les args d'un cran pour insérer `self` en R[0], pousse un frame avec `ctor_result = instance`.
4. À RETURN : si `ctor_result` non-nil, écrase R[0] avec l'instance (résultat = l'objet créé).

### CALL_METHOD (appel de méthode)

- Si R[cb] a `__class__` (instance) : garde `self` en R[cb], décale args → total = argc+1.
- Sinon (map simple/module) : décale les args depuis R[cb+2], pas de self → total = argc.

### Méta-méthodes (dispatch dans les opcodes arithmétiques)

Quand un opérande gauche est une instance, les opcodes ADD/SUB/MUL/DIV/MOD/NEGATE/EQ/LT/LE cherchent `__add`/`__sub`/... via `protoChainGet`. Si trouvé :
- Pousse un frame avec `return_dest = base+A` (registre résultat dans le frame appelant).
- À RETURN : si `return_dest >= 0`, copie R[0] du callee dans `regs[return_dest]`.

### Frame.ctor_result / Frame.return_dest

```cpp
struct Frame {
    ...
    Value ctor_result;   // non-nil = frame constructeur ; RETURN place l'instance dans R[0]
    int   return_dest = -1; // >= 0 = frame méta-méthode ; RETURN copie R[0] dans regs[return_dest]
};
```
