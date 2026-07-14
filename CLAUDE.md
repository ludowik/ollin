# Ollin — Scripting Language
> Minimaliste · Expressif · Dynamiquement typé · Compilé · Embarquable

## Règle obligatoire : écrire du code Ollin

Avant d'écrire **tout** fichier `.ol`, lire dans cet ordre :
1. `docs/grammar.ebnf` — syntaxe formelle du langage
2. `tests/syntax.ol` — exemples de référence

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
├── src/
│   ├── token.h        types Token (partagé Lexer → Parser)
│   ├── ast.h          nœuds AST  (partagé Parser → Compiler)
│   ├── opcode.h       format d'instruction 32-bit (make*/i*) + enum Op
│   ├── chunk.h/.cpp   bytecode (code, constantes dédupliquées, identifiants, funcs) — Compiler → VM
│   ├── value.h        Value taguée 16 o (ref-count, pivot T_STRING) + numValue/isFalsy
│   ├── string_table.h internement des chaînes (InternedStr, refcount)
│   ├── utf8.h         décodage UTF-8 partagé (utf8Count/ByteOffset/Step) — len, string.char/substr par codepoint
│   ├── closure.h      Upvalue + Closure (inclus en bas de value.h)
│   ├── lexer.h/.cpp
│   ├── parser.h/.cpp
│   ├── compiler.h/.cpp
│   ├── vm.h/.cpp
│   ├── source_registry.h/.cpp  registre de sources en mémoire (imports, playground)
│   ├── collections/   array.h/.cpp, map.h/.cpp (+ ValueHash/ValueEqual), iterator.h, range.h
│   ├── modules/       modules natifs : core, math, string, color, window, mouse, keyboard,
│   │                  graphics (graphics_module = 2D/fenêtre/boucle + graphics3d = 3D + graphics_quat = classe Quat, frontière graphics_internal.h ; graphics_stub = nil sans raylib),
│   │                  image (+ image_stub), + modules.h/.cpp, module_utils.h
│   ├── main.cpp       point d'entrée natif — pipeline Lexer | Parser | Compiler | VM
│   └── wasm_main.cpp  point d'entrée WASM (playground)
├── tests/             suite de tests (`bash tests/run.sh` = tout) : syntax.ol, regressions.ol, test_errors.sh + fixtures (utils_test*.ol, config.ol)
├── tools/             outillage : update_build_date.py (date de build, appelé en post-build CMake),
│                      native-gfx.sh (build raylib desktop → build-gfx/), run-headless.sh (exécution Xvfb),
│                      cm-entry.js (point d'entrée du bundle CodeMirror, esbuild via npm/CI),
│                      build-wasm.sh (build WASM via emscripten, 2ᵉ config CMake → docs/wasm/ ; cf. cible `wasm`)
├── bench/             benchmarks (.ol / .lua / .py)
└── docs/              tutoriel, playground, samples, wasm
```

## Web app monopage (docs/)

Le site (`docs/`) est une **SPA** : une seule page hôte, plusieurs vues montées à la demande.

- `docs/index.html` — **shell** minimal : `#view` (point de montage) + `<canvas id="canvas">` partagé (rangé dans `#canvas-home` hors exécution) ; charge `app.js`.
- `docs/app.js` — **routeur** par hash. `#/<vue>[/<ancre>]` change de vue ; `#<ancre>` (sans `/`) = ancre interne de la vue courante (défilement, pas de re-montage). `ctx.anchor` = sous-chemin après la vue (ancre tutoriel, ou paramètre de vue). Charge le runtime **WASM une seule fois** (`getOllin`, instance partagée) et déplace le canvas partagé dans la vue active.
- **Exemples en lecture directe** : `#/playground/sample/<fichier>` (et `#/run/sample/<fichier>`) ouvre un exemple `docs/samples/<fichier>` **depuis le dépôt, sans copie ni persistance** (re-`fetch` frais à chaque chargement → un refresh reprend la version du dépôt). Édition libre non enregistrée ; bouton « Créer un projet » pour forker dans IndexedDB. Les projets utilisateur (IndexedDB) restent le mode par défaut.
- `docs/views/<vue>.html` + `docs/views/<vue>.js` — chaque vue = un fragment (CSS + markup, `<style>` actif seulement monté) + un module `export function init(ctx) → cleanup()`. `ctx = { root, getOllin, hardReload, navigate }`. Vues : `tutoriel`, `playground`, `run`.
- `docs/playground.html` / `docs/run.html` — **redirections** vers `index.html#/playground` / `#/run` (anciens liens). La source unique est `docs/views/`.
- Modules partagés : `cm-lang.js` (langage CM6 Ollin), `cm-shared.js` (affichage CM), `pg-store.js` (projets IndexedDB), `pg-github.js`, `pg-run.js` (exécution/nav), `pg-format.js` (formateur).

**Règle** : `init(ctx)` doit retourner un `cleanup()` qui retire tout écouteur **global** (window/document) et met la boucle raylib en pause — sinon fuite/boucle fantôme au changement de vue.

## Syntaxe

> **La syntaxe et la sémantique du langage sont décrites dans [`docs/grammar.ebnf`](docs/grammar.ebnf).**
> CLAUDE.md ne documente **pas** la syntaxe — il décrit l'architecture et l'implémentation (opcodes, registres, structures internes). Pour toute question sur la forme du langage, lire la grammaire.

| Fichier | Propriétaire | Rôle |
|---|---|---|
| `tests/syntax.ol` | utilisateur | source de vérité syntaxe + suite de tests complète |
| `tests/regressions.ol` | Claude | non-régression des bugs corrigés en revue (coins peu couverts par `syntax.ol` : multi-retour closure/méthode, `super` 3 niveaux, clobber de registre sur appel 0-arg, lvalues chaînées, range ouvert…) |
| `docs/grammar.ebnf` | Claude | **grammaire formelle = référence de la syntaxe du langage** (dérivée de `syntax.ol`) |
| `docs/views/tutoriel.html` | Claude | tutoriel HTML (vue de la web app monopage) |
| `ollin-vscode/` | Claude | extension VS Code (colorisation) |

**Règle** : toute évolution de la syntaxe doit mettre à jour simultanément `grammar.ebnf` (référence), `syntax.ol`, `docs/views/tutoriel.html` et `ollin-vscode/`. CLAUDE.md n'est mis à jour que si l'implémentation (opcodes, stratégie de compilation, structures) change.

## Versionning

- Branche unique : **`main`** — tout le développement se fait directement sur main
- **Committer après chaque fonctionnalité complète** (feature atomique = 1 commit)
- **Ne jamais mettre Co-Authored-By dans les commits- pas de référence à Claude dans l'historique git par exemple
- Pusher sur `origin/main` après chaque commit
- `git restore <fichier>` pour annuler une modification non commitée, mais uniquement si tu respectes correctement les règles précédentes

**Toujours TOUT repousser sur `main`.** Si une consigne d'outillage/harness impose
de travailler sur une branche dédiée (ex. `claude/...`), reporter quand même le
résultat final sur `main` (merge/fast-forward + push `origin/main`). Le cas « branche
exceptionnelle » ne dispense jamais de livrer sur `main`.

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

Chaque benchmark est lancé **plusieurs fois (défaut 3, `RUNS=N` pour surcharger)** et on garde le **meilleur temps** : un run unique est trop sensible au bruit (contention CPU/cache) et peut afficher un coefficient faussé.

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

## Tests graphiques — DEUX chaînes qui MARCHENT (ne pas conclure « cassé »)

**Mémo** : ces deux moyens de test fonctionnent dans l'environnement (Xvfb, chromium,
GL logiciel et `build-gfx/` sont présents). Si un échec survient, c'est un détail
(chemin, serveur, sandbox), PAS une impossibilité — corriger le détail, ne pas
abandonner ni redemander.

### A. Desktop raylib sous Xvfb (le plus simple, PRIVILÉGIER)
Le build natif par défaut utilise le **stub graphique** (`graphics` = nil → un script
graphique NE tourne PAS avec `./build/ollin`). Pour le rendu réel sans navigateur :
- `build-gfx/ollin` est **construit automatiquement en tâche de fond au démarrage de
  session** (hook `session-start.sh`), gitignoré donc reconstruit à chaque reprise.
  **Avant un test xvfb**, vérifier qu'il est prêt : présence de `build-gfx/.ready`
  (ou de `build-gfx/ollin`). Si absent (build de fond pas fini ou échoué), le
  construire soi-même : `bash tools/native-gfx.sh` (rapide, source raylib en cache).
- `bash tools/native-gfx.sh` → `build-gfx/ollin` (raylib desktop, `-DOLLIN_NATIVE_RAYLIB=ON`).
  Réutilise la source raylib du build WASM (`build*/_deps/raylib-src`, github bloqué par
  le proxy → ni clone ni FetchContent ; pas de vendoring). Compile aussi = valide le C++
  raylib desktop.
- `bash tools/run-headless.sh <script.ol>` → exécute sous `xvfb-run` (GL llvmpipe).
- Capture : `graphics.screenshot("f.png")` — **chemin RELATIF** (raylib préfixe le CWD ;
  un chemin absolu échoue). La capture est **différée en fin de frame** → elle contient
  l'écran composé (pas la RenderTexture). Le script doit **terminer** (`graphics.quit()`
  après la capture) sinon la boucle tourne à l'infini sous Xvfb.
- Inspecter les pixels (pas de PIL/imagemagick) : via chromium (voir B) sur `file://…png`
  → `drawImage` + `getImageData` (centroïde, bbox, couleur d'un pixel).

### B. Web / WASM via Playwright (chromium)
- chromium : `/opt/pw-browsers/chromium-1194/chrome-linux/chrome` ; `playwright` est dans
  `node_modules` (lancer node depuis la racine du repo). `chromium.launch({ executablePath })`.
- Charger une page/capture : `file://` marche direct (aucun réseau). Pour le playground,
  servir `docs/` en local puis charger `http://127.0.0.1:PORT/index.html#/playground`,
  injecter du code via `window.__ollinView.dispatch(...)`, cliquer `#run-btn`, puis lire
  `#canvas` (drawImage→getImageData) = **vrai composite affiché**.
- ⚠️ Piège : lancer le serveur HTTP en arrière-plan (`python3 -m http.server &`) dans la
  MÊME commande shell peut faire échouer la commande (exit 144, bind réseau/sandbox).
  Contournements : `dangerouslyDisableSandbox`, `--bind 127.0.0.1`, ou **préférer la
  chaîne A (xvfb)** qui n'a pas besoin de serveur. Le `file://` d'un PNG, lui, marche.
  **Le plus fiable pour tester le playground** : un **serveur HTTP node in-process**
  dans le MÊME script que Playwright (`http.createServer` servant `docs/` avec les
  bons MIME .js/.wasm/.json, puis `chromium.launch`) — évite le process python en
  arrière-plan (exit 144). Charger `http://127.0.0.1:PORT/index.html#/…`, injecter du
  code via `window.__ollinView.dispatch(...)`, cliquer `#run-btn`, lire `#canvas`.

Le WASM reste la cible de déploiement (playground). Ne rien committer de `build-gfx/`
(ignoré par `build*/`).

## Style C++ (formatage)

Les règles mécaniques sont dans `.clang-format` (référence autoritaire). Ce qui suit complète ce que clang-format ne couvre pas.

| Règle | Valeur |
|-------|--------|
| Indentation | 4 espaces, pas de tabs |
| Colonne max | 120 |
| Accolades | K&R : ouvrante sur la même ligne |
| Alignement colonne | Non : un seul espace entre type et nom |
| One-liners | Interdits : corps de fonction toujours sur une nouvelle ligne indentée |
| Une instruction par ligne | Strict : jamais deux `;` sur la même ligne — boucles, `if`, `return` toujours sur des lignes séparées |
| Pointeurs/références | Collés au type : `int*`, `const Foo&` |
| Espace avant `(` | Uniquement pour les mots-clés (`if`, `while`, `for`) — jamais pour les appels |
| Includes | Header propre en premier (`"foo.h"`), puis STL (`<vector>`) |

**Visitor/StmtQuery** : chaque `visit()` override sur sa propre ligne avec corps indenté, même si court :
```cpp
void visit(const WhileStmt& s) override {
    run(s.body);
}
```

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
| AND / OR      | ABC    | A=dst, B=lhs, C=rhs        | R[A] = 1.0 si vrai sinon 0.0 — **réservé aux comparaisons chaînées** ; les opérateurs `and`/`or` du langage compilent en court-circuit (JUMP_IF_FALSE + MOVE, sémantique valeur Lua) |
| EQ/NEQ/GT/LT/GE/LE | ABC | A=dst, B=lhs, C=rhs  | R[A] = 1.0 si vrai sinon 0.0 ; GT/LT/GE/LE : nombres OU deux strings (ordre lexicographique) |
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
| FOR_PREP      | ABx    | A=ctl, Bx=exit_addr        | for numérique : R[A..A+2]=i,limite,pas ; valide, fige int/float ; vide → ip=Bx ; sinon (int) R[A+1] ← compteur de tours restants, tombe dans le corps |
| FOR_LOOP      | ABx    | A=ctl, Bx=body_addr        | int : si compteur R[A+1]≠0 → décrémente, i+=pas, ip=Bx (corps) ; sinon sortie. float : i+=pas + comparaison de limite |
| LOAD_FUNC     | ABx    | A=dest, Bx=func_idx        | R[A] = T_FUNCTION (référence à funcs[Bx])        |
| CALL_DYN      | ABC    | A=arg_base, B=func_reg, C=argc | appel via T_FUNCTION ou T_CLOSURE dans R[B]  |
| MAKE_CLOSURE  | ABx    | A=dest, Bx=func_idx        | R[A] = Closure{func_idx, capture upvals depuis frame courant} |
| GET_UPVAL     | AB     | A=dest, B=upval_idx        | R[A] = upval[B]  (ouverte: regs[base+idx], fermée: uv.val) |
| SET_UPVAL     | AB     | A=src, B=upval_idx         | upval[B] = R[A]                                  |
| NEW_CLASS     | A      | A=dest                     | R[A] = nouvelle classe vide (T_CLASS)            |
| CALL_METHOD   | ABC    | A=recv_base, B=0, C=argc   | R[A]=receiver, R[A+1]=fn, R[A+2..]=args ; self auto si instance |
| SPREAD_RESULTS| AB     | A=base, B=n                | destructuration multi-retour : met R[A+last_results..A+n-1] à nil (émis après l'appel ; last_results = nb réel de valeurs renvoyées) |
| HALT          | —      |                            | arrêt                                            |

## Globales moteur (engine-injected globals)

Des globales sont injectées par le moteur, sans déclaration `global` dans le script :

| Nom | Type | Description |
|-----|------|-------------|
| `deltaTime` | FLOAT | Secondes écoulées depuis la frame précédente (`GetFrameTime()`) |
| `elapsedTime` | FLOAT | Secondes écoulées depuis le démarrage du programme (somme des deltaTime) |
| `W` | INTEGER | Largeur de la zone de rendu (défaut : `window.width` selon l'environnement) |
| `H` | INTEGER | Hauteur de la zone de rendu (défaut : `window.height`) |
| `CW` | FLOAT | Centre X de la zone de rendu (`W / 2`) |
| `CH` | FLOAT | Centre Y de la zone de rendu (`H / 2`) |

**Implémentation** :
- `declared_globals_` les contient (pré-ajoutés dans `Compiler::compile()`) → le compilateur accepte ces noms sans `global`.
- `VM::execute()` initialise `deltaTime`/`elapsedTime` à `0.0`, `W`/`H` (int) aux dimensions de `window` (lues via `makeBuiltinModule("window")`) et `CW`/`CH` (float) à `W/2`/`H/2` **avant le top-level** — ainsi `graphics.canvas(W, H)` fonctionne dès le script principal.
- `gfx_canvas()` (graphics_module.cpp) **repositionne** `W`/`H`/`CW`/`CH` sur les dimensions logiques réelles à chaque `graphics.canvas(w, h)` (via `setGlobal`) → les globales suivent la taille effective du canvas, même si elle diffère du défaut `window`.
- `VM::setGlobal(name, value)` — méthode publique qui trouve l'identifier par nom et met à jour `globals[i]`. Appelée par `callUpdateIfAny()` dans `graphics_module.cpp` avant chaque frame.
- `s_elapsed_time` (statique dans `graphics_module.cpp`) est remis à 0 à chaque `gfx_run()`.

**Règle d'animation** : utiliser `elapsedTime` (ou `deltaTime` accumulé manuellement) plutôt que `time()`. `time()` utilise `Date.now()` dans le navigateur (précision réduite) ; les globales moteur sont basées sur `GetFrameTime()` / `performance.now()`, plus précis et sans artefact.

## Affichage 3D + éclairage (graphics_module.cpp)

La 3D s'appuie sur raylib (`Camera3D`, `BeginMode3D`/`EndMode3D`, `GenMesh*`) mais les **solides pleins** passent par un **batcher retained à instancing** avec un shader Blinn-Phong custom. Fonctionne desktop (GL 3.3) **et** WebGL2/GLES3 (vérifié).

- **Intégration frame** : `graphics.begin3d(cam)` → `BeginMode3D` (perspective + depth test) et réinitialise les buckets ; `graphics.end3d()` flushe les buckets puis `EndMode3D` (restaure l'ortho 2D → HUD 2D possible ensuite). Bloc ouvert **dans** `draw()`, donc dans la `RenderTexture` `s_target`.
- **Batcher instancié** : `cube/sphere/cylinder/plane` en `fill` n'affichent rien — ils **empilent** une instance `{transfo = local·pileMatrices, tint = couleur fill}` dans un bucket `(shape, texture)` (`s_buckets`), où `local = scale·translate` (placement) et `pileMatrices = rlGetMatrixTransform()` capturée à l'appel. `end3d`/`flush3dBuckets` résout chaque bucket en **UN** `DrawMeshInstanced` custom (réplique de raylib + **2ᵉ VBO d'instance couleur** → couleur PAR INSTANCE) avec des VBO d'instance **persistants** (create/grow + `glBufferSubData`, pas de churn). Meshes unitaires en cache (`GenMeshCube/Sphere/Cylinder/Plane`) ; draw indexé ou non selon `mesh.indices`. Le **fil de fer** (`stroke`), `grid`, `line3d`, `point3d` restent en **immédiat non éclairé** (dessinés pendant la collecte ; `flush3dBuckets` fait `rlDrawRenderBatchActive` avant les draws instanciés).
- **Transformations 3D** : `translate(x,y[,z])`, `rotate(deg[,ax,ay,az])`, `rotateX/Y/Z(deg)`, `scale(s|sx,sy|sx,sy,sz)` pilotent la pile rlgl. `begin3d` fait un `rlPushMatrix` (refermé par `end3d`) → tout le bloc est en mode « transform » : translate/rotate/scale écrivent dans `RLGL.State.transform` (espace monde, lu par `rlGetMatrixTransform()`) **qu'ils soient encadrés par `push`/`pop` ou « nus »** (cumulatifs). Chaque instance fige cette transfo (`pushInstance`), et les primitives immédiates l'appliquent (`transformRequired`) → même sémantique pour tous. Le MVP du flush utilise `s_view3d` (vue figée au `begin3d`), la modelview restant = vue.
- **Shader** (`loadLitShader`, embarqué en littéral, `#version 330` desktop / `300 es` WASM via `#ifdef __EMSCRIPTEN__`) : `instanceTransform` (auto) + `instanceColor` (attribut custom via `GetShaderLocationAttrib`) + `texture0`. `final = texture(uv) × tint`, puis Blinn-Phong (ambient + 1 lumière). **Opt-in** : sans lumière (`s_lighting_used=false`), ambient forcé à blanc + lumière off ⇒ rendu plat (aucune régression).
- **Éclairage** (phase 1 : ambient + 1 lumière) : `graphics.ambient(v|couleur)` ; `graphics.light("dir"|"point", x,y,z [,couleur])` renvoie un objet **classe `Light`** (patron `makeClass`) — méthodes `set_dir`/`set_pos`/`set_color`/`enable` qui mutent l'état global via `applyLightFromInstance`. Réinitialisé à chaque `gfx_run` (`reset3dLightingState`, statiques persistants en WASM).
- **Textures** : `graphics.texture(img)` lit l'id GL via `image_gl_texid(handle.id)` (accessor ajouté à image_module) ; `noTexture()` → texture blanche 1×1 (`whiteTexId`). `s_cur_tex3d` se comporte comme `fill`/`stroke` : remis à 0 dans `resetStyles` chaque frame.
- **Atlas de tuiles (terrain voxel)** : `graphics.tileset(img, cols, rows)` déclare un atlas (grille de tuiles, filtrage NEAREST) ; `graphics.tiles(top, side, bottom)` / `graphics.tile(t)` fixent les tuiles du prochain cube (état, comme `fill` ; -1 = aucune). Un **3ᵉ attribut d'instance** `instanceTile` (vec3, VBO `vboT` pour les chunks / `s_inst_vbo_tile` pour l'immédiat) porte le triplet ; le shader **choisit la tuile selon la normale** (dessus/côté/dessous) et échantillonne l'atlas (`(cell + fract(uv)) / atlasGrid`, inset anti-bleeding). `tile.x < 0` → chemin classique (texture0 @ fragTexCoord, modèles/immédiat). **1 seul draw call par chunk conservé** — l'atlas est lié par `drawChunk` (à la place du blanc). L'atlas est généré en Ollin via le module `image` (`create`/`set_pixel`/`end_pixels` — render texture, échantillonnée SANS flip V car mise à jour par `UpdateTexture`, pas par rendu).
- **Caméra** : classe native `Camera` ; `graphics.camera(...)` renvoie une INSTANCE (`px,py,pz, tx,ty,tz, fovy`). Méthodes : `set_pos`, `look_at`, `move`, `orbit(angle rad, rayon [, hauteur])`. `cameraFromMap()` la relit (up +Y, perspective) ; `s_cam3d` fournit `viewPos` au shader.
- **Profondeur** : la RT raylib porte un depth buffer (desktop + GLES) ; `graphics.clear(couleur opaque)` efface couleur **+ depth** (`rlClearScreenBuffers`).
- **Garde-fou** : `s_in_3d` ; `runUserCallbacks` appelle `end3dInternal()` si `draw()` oublie `end3d` (flush + rééquilibre la pile). `end3d` idempotent.
- **Quaternions** (`graphics_quat.cpp`, math raymath pure, fichier séparé) : classe native `Quat` ; fabriques `graphics.quat()`/`quat_axis(ax,ay,az,deg)`/`quat_euler(pitch,yaw,roll)` (**degrés**) ; méthodes `mul`/`slerp`/`normalize`/`inverse`/`rotate_vec` (renvoient de NOUVELLES instances, valeurs immuables). `graphics.rotateq(q)` (dans graphics3d.cpp) applique `QuaternionToMatrix(q)` via `rlMultMatrixf` (gauche-multiplie comme `rlRotatef` → compose comme `rotate`). `quatFromInstance()`/`makeQuatInstance()` = pont graphics3d↔graphics_quat.
- **Perf/limites** : 1 draw call par `(shape, texture)` — le nombre de **couleurs** n'ajoute pas de draw call (couleur par instance). `cylinder` est **mono-rayon** (`x,y,z,r,h`) : contrainte du mesh unitaire figé. Models externes = extension additive (bucket déjà keyé `(mesh, texture)`).

## Déclaration de variables (implémentation de l'enforcement)

> Règle de langage (`var` = locale, `global` = globale, obligation de déclaration) : voir `grammar.ebnf` (`varDecl`, `globalDecl`, `assignStmt`).

- Message d'erreur émis : `undeclared variable '<nom>' (use 'var' or 'global')`.
- `declared_globals_` (set) contient : noms de classes, tous les noms déclarés par `global`, les modules et builtins, et les **globales moteur** (`deltaTime`, `elapsedTime`).
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

**Portée des variables de boucle** : `var1`/`var2` sont **locales à la boucle** — pas collectées par `collectLocals` ; le compilateur les lie dans `local_regs_` le temps du corps puis **restaure** l'ancienne liaison (ou la supprime) → pas de fuite après la boucle (y référer = « undeclared variable »), une variable externe de même nom est masquée puis restaurée. Recyclage des registres : si `bodyHasFunc(body)` (une closure du corps peut capturer la variable via upvalue ouverte), les registres de boucle restent **réservés** après la sortie pour ne pas être réécrits (closures → valeur finale, cohérent) ; sinon ils sont recyclés.

**Chemin rapide numérique** (`compileNumericFor`) : déclenché quand `iter_expr` est un **RangeExpr littéral inclus aux deux bornes** (`incl_left && incl_right`) avec **1 variable** — couvre `for i = a, b[, step]` et `for i in [a;b]`. Pas de `Range` ni d'itérateur ni de dispatch virtuel.  
- 3 registres consécutifs `ctl/ctl+1/ctl+2` = `i / limite / pas`.  
- `FOR_PREP ctl, →sortie` : valide (nombres, pas≠0), fige le type (tout int → int64 ; sinon tout converti en double) ; si la boucle est vide → saute à la sortie ; sinon **tombe dans le corps** (1re itération, `i` non pré-décrémenté → pas de wrap à la borne basse). **Chemin int** : calcule une fois le **compteur de tours restants** `(limite − i)/pas` en arithmétique non signée (sûr au débordement) et le stocke dans `R[ctl+1]` (à la place de la limite, désormais inutile).  
- `FOR_LOOP ctl, →corps` : **chemin int** : si le compteur `R[ctl+1] ≠ 0` → le décrémente, `i += pas`, saut vers le corps ; sinon sortie. Plus de garde anti-débordement ni de comparaison de limite par tour (le compteur garantit que `i+pas` reste dans la plage). **Chemin float** : `i += pas` puis comparaison de limite (`≤` si pas>0, `≥` sinon).  
- **Alias de la variable** (`loopBodyAliasSafe`) : si le corps n'écrit jamais `i` (pas de réassignation, pas de lambda, pas de structure imbriquée), `var1` est aliasée sur `ctl` → **pas de copie par itération**. Sinon un registre séparé `var_reg` reçoit `i` via un `MOVE` en tête de corps à chaque tour (compteur isolé → modifier `i` dans le corps n'affecte pas l'itération). La règle « rejeter toute structure imbriquée » empêche aussi la corruption des boucles `for` imbriquées (l'externe n'est pas aliasée). Gain mesuré : ~−24 % sur la boucle `s += i` 10M.  
Les ranges ouverts (`[a;b[`, `]a;b]`…) et `for k,v in …` gardent le chemin itérateur ci-dessous.

**Itérateur** (`for [k,] v in expr`) : `MAKE_ITER` crée l'itérateur (MapIterator snapshot, ArrayIterator ref, ou RangeIterator), stocké dans `[block+0]`.  
- 2 vars : `FOR_ITER_NEXT` → `[block+1]`=key, `[block+2]`=val. 3 registres + 1 temp source.  
- 1 var  : `FOR_ITER_NEXT1` → `[block+1]`=primary (val si `primary_is_val()`, sinon key). 2 registres + 1 temp source.  
`var1`/`var2` sont aliasées directement sur `[block+1]`/`[block+2]` (pas de copie : `FOR_ITER_NEXT` les réécrit à chaque tour → modifier la variable dans le corps est sans effet).  
`Iterator::primary_is_val()` : `ArrayIterator`=true, `RangeIterator`=true, `MapIterator`=false.

## Type range (implémentation)

> Notation d'intervalles `[a;b]` / `]a;b[` / step / first-class : voir `grammar.ebnf` (`rangeLit`).

`MAKE_RANGE` (opcode ABC) : A=dest, B=base (start=R[B], end=R[B+1], step=R[B+2] si has_step), C=flags (bit0=incl_right, bit1=has_step). L'ajustement open-left est émis par le compilateur via ADD avant MAKE_RANGE.  
`T_RANGE = 11` — Range* ref-counted avec `{start, end, step, incl_right}` (entiers uniquement).

## Type map (implémentation)

> Syntaxe littérale JSON-like, accès `m["k"]` / `m.k`, sémantique : voir `grammar.ebnf` (`mapLit`, `indexAssign`).

Implémentation : `Map { robin_hood::unordered_map<Value,Value,ValueHash,ValueEqual> data; int refcount; }` — hashmap **`robin_hood`** (mono-header vendorisé `libs/robin_hood.h`, même lib que le `StringTable` ; variante *node* car `Value` n'est pas trivialement copiable), ref-counted, recyclé via `MapPool`.  
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

**Ordre des tags = invariant de perf** : tous les types **non ref-comptés** d'abord (0..4), puis le pivot `T_STRING` et tous les **ref-comptés** contigus (5..11). Ainsi `tag < T_STRING` sépare en **un seul test** les valeurs sans gestion mémoire (nil/int/float/function/builtin) de celles à retain/release (`Value::retain()`/`release()`). Tout nouveau type ref-compté doit être ajouté **après** le pivot, tout type non compté **avant**.

| tag        | valeur (uint8_t) | union actif | plage / note        |
|------------|-----------------|-------------|---------------------|
| T_NIL      | 0               | —           | non ref-compté      |
| T_INTEGER  | 1               | ival (int64_t) | ±2^63            |
| T_FLOAT    | 2               | dval (double) | IEEE 754 double   |
| T_FUNCTION | 3               | ival (int64_t, = func_idx) | index dans chunk.funcs (non compté) |
| T_BUILTIN  | 4               | ival (pointeur natif) | fonction native (non compté) |
| T_STRING   | 5               | sptr (InternedStr*) | **pivot** — ref-counted, str_hash = sptr->hash |
| T_MAP      | 6               | mptr (Map*) | ref-counted     |
| T_ARRAY    | 7               | aptr (Array*) | ref-counted   |
| T_ITERATOR | 8               | iptr (Iterator*) | ref-counted |
| T_CLOSURE  | 9               | cptr (Closure*) | ref-counted, holds func_idx + upvals |
| T_CLASS    | 10              | mptr (Map*) | ref-counted ; même layout que T_MAP, distinct pour CALL_DYN |
| T_RANGE    | 11              | rptr (Range*) | ref-counted ; intervalle entier      |

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
    bool  negate_result = false; // RETURN nie (logique) R[0] avant return_dest
};
```

`negate_result` : utilisé par `<>` (via `__eq`) et par les comparaisons où
l'instance est du côté « inverse » (`a > b` avec `a` instance ⟺ `not a.__le(b)`,
`a >= b` ⟺ `not a.__lt(b)`, symétrique pour `<`/`<=`). Le résultat de la
méta-méthode est nié avant d'être écrit dans `return_dest`.

`VM::last_results_` : nombre de valeurs produites par le dernier appel/retour,
consommé par `SPREAD_RESULTS` pour mettre à `nil` les cibles d'une
destructuration multi-retour au-delà de ce que l'appel a réellement renvoyé.
