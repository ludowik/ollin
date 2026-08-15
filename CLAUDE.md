# Ollin — Scripting Language
> Minimaliste · Expressif · Dynamiquement typé · Compilé · Embarquable

## Collaboration

**Langue et format de réponse (règle permanente)** : répondre **toujours en
français**. Les rapports, revues de code, synthèses et résultats sont rendus en
**texte lisible** (titres, listes, prose) — **jamais** de JSON brut ni de dump de
structure de données comme livrable à l'utilisateur, même si un outil/skill
produit du JSON en interne (le convertir en rapport lisible avant de le présenter).

**Style de rédaction (règle permanente)** : écrire des **phrases complètes** en
français correct. Le style télégraphique est proscrit : pas de fragments sans
verbe (« Vérifié : … », « Corrigé et poussé. »), pas de listes de mots-clés en
guise d'explication. Rester **simple, précis et concis** — des phrases courtes et
claires plutôt que de longs développements. Éviter les anglicismes fabriqués
(« differ » un fichier, une sortie « diffée ») : dire « comparer les sorties ».
Ne pas inventer de jargon interne pour désigner les artefacts du projet (un
fichier de test est un « script de test », pas une « torture »).

Avant d'agir, délimiter le périmètre exact de la demande. Si plusieurs
interprétations raisonnables divergent — surtout si l'une déborde de la cible —
poser une question de clarification **brève** avant de coder ; ne pas deviner
large. Ne modifier que ce qui est demandé (pas de refactor/nettoyage collatéral
non sollicité). Agir sans confirmation seulement si l'intention est univoque.

**`todo.md` n'est PAS à Claude (règle permanente)** : ne jamais le lire pour se donner
du travail, ne jamais l'éditer, ne jamais proposer ce qu'il contient. Traiter uniquement
ce que l'utilisateur demande.

**Plan ⇒ pas d'implémentation sans GO explicite (règle permanente).** Une demande
de *plan* (ou « plan pour… ») n'autorise JAMAIS à coder. Ne commencer l'implémentation
qu'après un **GO explicite** de l'utilisateur (« GO », « implémente », « vas-y »).
Répondre à mes questions de cadrage/design **ne vaut pas** GO. En cas de doute,
demander — ne pas deviner.

## Règle obligatoire : écrire du code Ollin

Avant d'écrire **tout** fichier `.ol`, lire dans cet ordre :
1. `docs/grammar.ebnf` — syntaxe formelle du langage
2. `tests/syntax.ol` — exemples de référence

Tester ensuite avec `./build/ollin <script>` avant tout build WASM.  
Ces deux étapes sont **non négociables**, quelle que soit la taille du script.

## Stack
- Implémentation : **C++17**
- Build : **CMake** (cross-platform)
- Compilateurs supportés : **GCC et Clang**, indifféremment (seule contrainte : le *computed-goto*, extension GNU absente de MSVC — voir « Règle computed-goto »)
- Cibles : Windows, Linux, macOS, iOS, Android, wasm
- La cible **wasm** compile avec **Clang** : `emcc` n'est pas un compilateur mais une enveloppe autour de LLVM/Clang (`$EMSDK/upstream/bin/clang`). Le computed-goto y fonctionne donc, et le playground exécute la **même** VM que le binaire natif — aucun repli vers un `switch`.
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
│   │                  image (+ image_stub), ui (+ ui_stub), tween, + modules.h/.cpp, module_utils.h
│   │                  array_module = pseudo-méthodes des tableaux (interne, PAS un module global)
│   ├── main.cpp       point d'entrée natif — pipeline Lexer | Parser | Compiler | VM
│   └── wasm_main.cpp  point d'entrée WASM (playground)
├── tests/             suite de tests (`bash tests/run.sh` = tout) : syntax.ol, regressions.ol, test_errors.sh + fixtures (utils_test*.ol, config.ol)
├── tools/             outillage : update_build_date.py (date de build, appelé en post-build CMake),
│                      native-gfx.sh (build raylib desktop → build-gfx/), run-headless.sh (exécution Xvfb),
│                      cm-entry.js (point d'entrée du bundle CodeMirror, esbuild via npm/CI),
│                      build-wasm.sh (build WASM via emscripten, 2ᵉ config CMake → docs/wasm/ ; cf. cible `wasm`),
│                      ollin-vscode/ (extension VS Code, colorisation)
├── bench/             benchmarks (.ol / .lua / .py)
└── docs/              tutoriel, playground, samples, wasm
```

## Web app monopage (docs/)

Le site (`docs/`) est une **SPA** : une seule page hôte, plusieurs vues montées à la demande.

- `docs/index.html` — **shell** minimal : `#view` (point de montage) + `<canvas id="canvas">` partagé (rangé dans `#canvas-home` hors exécution) ; charge `app.js`.
- `docs/app.js` — **routeur** par hash. `#/<vue>[/<ancre>]` change de vue ; `#<ancre>` (sans `/`) = ancre interne de la vue courante (défilement, pas de re-montage). `ctx.anchor` = sous-chemin après la vue (ancre tutoriel, ou paramètre de vue). Charge le runtime **WASM une seule fois** (`getOllin`, instance partagée) et déplace le canvas partagé dans la vue active.
- **Exemples en lecture directe** : `#/playground/sample/<fichier>` (et `#/run/sample/<fichier>`) ouvre un exemple `docs/samples/<fichier>` **depuis le dépôt, sans copie ni persistance** (re-`fetch` frais à chaque chargement → un refresh reprend la version du dépôt). Édition libre non enregistrée ; bouton « Créer un projet » pour forker dans IndexedDB. Les projets utilisateur (IndexedDB) restent le mode par défaut.
- `docs/views/<vue>.html` + `docs/views/<vue>.js` — chaque vue = un fragment (CSS + markup, `<style>` actif seulement monté) + un module `export function init(ctx) → cleanup()`. `ctx = { root, getOllin, hardReload, navigate }`. Vues : `tutoriel`, `playground`, `run`.
- **Aperçu d'une ressource (vue `playground`)** : cliquer une ressource du rail l'affiche **à la place de l'éditeur** — `#res-view`, frère de `#editor-wrap` dans `#editor-main`, l'un masquant l'autre. Une image est rendue sur un damier (sinon un fond transparent se confondrait avec le panneau) avec ses dimensions et son poids ; tout autre format n'a qu'une fiche d'information. `currentRes` (nom, ou `null` = on édite) sert aussi aux deux rails pour la ligne active, si bien qu'un seul élément paraît sélectionné. Ouvrir un script, re-cliquer la ressource affichée ou la supprimer ramène à l'éditeur.
- **Capture d'écran (mode plein écran, vue `run`)** : le bouton « Capture » range un PNG dans les **ressources du projet actif** (`project.resources[nom] = {b64, ext}`), puis le déclare au moteur (`preloadImage`) → utilisable aussitôt par `image.load(nom)`. L'image vient du MOTEUR, en deux temps (`requestCapture` / `takeCapture`, bindings de `wasm_main.cpp`) : elle ne peut être lue qu'en **fin de frame**, et `canvas.toDataURL` rendrait une image vide (le contexte WebGL n'a pas `preserveDrawingBuffer`). En pause, la vue reprend la boucle le temps d'une frame. Un exemple lu depuis le dépôt n'a pas de projet où ranger l'image → message explicite.
- `docs/playground.html` / `docs/run.html` — **redirections** vers `index.html#/playground` / `#/run` (anciens liens). La source unique est `docs/views/`.
- Modules partagés : `cm-lang.js` (langage CM6 Ollin), `cm-shared.js` (affichage CM), `pg-store.js` (projets IndexedDB), `pg-github.js`, `pg-run.js` (exécution/nav), `pg-format.js` (formateur).

**Formateur (`pg-format.js`)** : réindentation ligne par ligne, sans AST. Deux règles à
retenir avant d'y toucher — une ligne qui ouvre à la fois un bloc et un délimiteur
(`f(x, func()`) ne vaut qu'**un** niveau (le bloc « absorbe » les délimiteurs de sa ligne
d'ouverture), et les crochets ne sont comptés que sur les lignes **sans `;`**, un range
(`[a;b[`) pouvant fermer avec `[`. Tout mot-clé ouvrant un bloc doit figurer dans
`OPENERS` : `enum` y manquait depuis son ajout au langage.

**Règle** : `init(ctx)` doit retourner un `cleanup()` qui retire tout écouteur **global** (window/document) et met la boucle raylib en pause — sinon fuite/boucle fantôme au changement de vue.

## Syntaxe

> **La syntaxe et la sémantique du langage sont décrites dans [`docs/grammar.ebnf`](docs/grammar.ebnf).**
> CLAUDE.md ne documente **pas** la syntaxe — il décrit l'architecture et l'implémentation (opcodes, registres, structures internes). Pour toute question sur la forme du langage, lire la grammaire.

Le tableau ci-dessous répartit la **charge d'entretien** : qui tient la plume sur
quel fichier au quotidien. Ce n'est **pas** une frontière de propriété — tout le
dépôt appartient à l'utilisateur. Corollaire : quand une modification rend une
ligne obsolète dans un fichier « à l'utilisateur » (une signature documentée dans
un commentaire, par exemple), c'est à Claude de la corriger, sans s'en abstenir au
prétexte de cette colonne.


| Fichier | Maintenu par | Rôle |
|---|---|---|
| `tests/syntax.ol` | utilisateur | source de vérité syntaxe + suite de tests complète |
| `tests/regressions.ol` | Claude | non-régression des bugs corrigés en revue (coins peu couverts par `syntax.ol` : multi-retour closure/méthode, `super` 3 niveaux, clobber de registre sur appel 0-arg, lvalues chaînées, range ouvert…) |
| `docs/grammar.ebnf` | Claude | **grammaire formelle = référence de la syntaxe du langage** (dérivée de `syntax.ol`) |
| `docs/views/tutoriel.html` | Claude | tutoriel HTML (vue de la web app monopage) |
| `tools/ollin-vscode/` | Claude | extension VS Code (colorisation) |

**Règle** : toute évolution de la syntaxe doit mettre à jour simultanément `grammar.ebnf` (référence), `syntax.ol`, `docs/views/tutoriel.html` et `tools/ollin-vscode/`. CLAUDE.md n'est mis à jour que si l'implémentation (opcodes, stratégie de compilation, structures) change.

**Règle (permanente) : exécuter `bash tests/run.sh` avant CHAQUE commit, sans exception.**
Pas seulement après une évolution du moteur (VM, compilateur, modules natifs) : aussi pour un
exemple `.ol`, la web app, un commentaire, la documentation. La suite couvre `syntax.ol`,
`regressions.ol`, `test_errors.sh` et `check_naming.sh`, et dure quelques secondes — juger au
cas par cas qu'un changement « ne peut rien casser » est un pari qui coûte plus cher qu'elle.
Un commit ne part que sur un « TOUT VERT ».

**Tenu par git, pas par la mémoire** : `tools/git-hooks/pre-commit` (versionné) recompile
`build/ollin` puis lance la suite, et refuse le commit si l'un des deux échoue. Il est branché
par `core.hooksPath` au démarrage de session (`.claude/hooks/session-start.sh`) — `.git/hooks`
n'étant pas versionné, il disparaîtrait à chaque conteneur neuf. La recompilation est
essentielle : sans elle, une modification C++ non compilée serait validée par l'ANCIEN binaire.
`git commit --no-verify` le contourne, à réserver aux cas où la suite ne peut pas tourner.

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
L'extension GNU employée s'appelle « labels comme valeurs » : `&&etiquette` donne l'adresse d'une étiquette (interdit en C++ standard) et `goto *ptr` saute vers une adresse calculée. Chaque opcode a ainsi **son propre** saut indirect, que le prédicteur de branchement apprend à anticiper, au lieu du saut unique d'un `switch`. Corollaire : tous les gestionnaires vivant dans une seule fonction, la disposition du code machine influe sur les mesures (cf. « Commande perf »). Disponible avec GCC comme avec Clang, donc **aussi en wasm** (emcc = Clang).  
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

Les trois langages mesurent le **temps PROCESSEUR**, pas le temps écoulé : `cpuTime()` en Ollin, `os.clock()` en Lua, `time.process_time()` en Python. Ne pas utiliser `time()` dans un benchmark Ollin : il lit une horloge murale que le système peut ajuster en cours de route (NTP), d'où des valeurs aberrantes isolées.

| # | Benchmark | Script |
|---|-----------|--------|
| 1 | fib(35) récursif | `bench/bench_fib.*` |
| 2 | Boucle numérique 10M | `bench/bench_loop.*` |
| 3 | Création/accès map 100K | `bench/bench_objects.*` |
| 4 | Accès array 1M | `bench/bench_array.*` |
| 5 | Appels de fonctions 1M | `bench/bench_calls.*` |
| 6 | Chaînes : concaténation + interpolation 200K | `bench/bench_strings.*` |
| 7 | Classes : instanciation, méthode, héritage 200K | `bench/bench_classes.*` |
| 8 | Itération `for … in` tableau + map 2.4M | `bench/bench_iter.*` |
| 9 | Mandelbrot 200×200 (arithmétique flottante) | `bench/bench_float.*` |

Chaque benchmark affiche une **somme de contrôle** identique dans les trois langages (longueur totale, accumulateur, nombre d'itérations) : elle vérifie que les trois versions font bien le même travail. Toute divergence signale une traduction fautive, pas un écart de performance.

**Aucun environnement n'est normatif — tous sont des cibles** (cf. « Stack ») :
- `bench_all.sh` localise seul les interpréteurs : Lua via `lua5.4`/`lua54`/`lua` dans le PATH (ou `C:\Tools\lua\lua55.exe` sous Windows), Python via `python3`/`python`. Une colonne affiche `N/A` si l'interpréteur manque.
- **Ne jamais comparer des chiffres obtenus sur deux machines, ni sur deux sessions différentes** : ni les temps absolus ni les coefficients ne sont transposables (matériel, compilateur, version des interpréteurs). Un tableau de benchmarks ne vaut que pour la machine et le moment où il a été produit.
- Pour attribuer un écart à un changement de code, mesurer les binaires comparés sur la **même machine, dans la même série** (cf. tourniquet ci-dessous).

**Règles strictes pour les comparaisons :**
- Ne pas inventer de raison pour expliquer les écarts de performance — s'en tenir aux faits mesurés.
- **Sensibilité à la disposition du code (mesurée, ±7 % sur `fib`)** : tous les gestionnaires
  d'opcodes vivent dans une seule fonction (`run_goto`, computed-goto), donc modifier
  **n'importe quel** gestionnaire déplace l'adresse de tous les autres et change le
  comportement du cache d'instructions. Fait vérifié : ajouter 32 `nop` dans `op_TRY`, que
  `bench_fib.ol` n'exécute jamais, rend `fib` **7 % plus rapide**. Corollaire : un écart de
  quelques pour cent sur un benchmark dont le chemin d'exécution ne touche pas le code
  modifié n'est **pas** un coût réel — ne pas chercher à l'« optimiser », et surtout ne pas
  figer une disposition favorable (le prochain changement la défera). Pour attribuer un
  écart à un commit, mesurer en **tourniquet** (tous les binaires une fois par tour, puis
  minimum par binaire) : une mesure au meilleur de trois est trop bruitée.

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
- **Lire des pixels exige de vider le batch rlgl d'abord** (`rlDrawRenderBatchActive()`) :
  la composition de la render texture n'est qu'un quad EN ATTENTE, et lire l'écran avant son
  exécution rend une image entièrement **noire** (constaté au navigateur sur la capture du
  mode plein écran). `flush_pending_screenshot` vide donc le batch une fois, pour le fichier
  comme pour la capture mémoire.
- Capture : `graphics.screenshot("f.png")` — **chemin RELATIF** (raylib préfixe le CWD ;
  un chemin absolu échoue). La capture est **différée en fin de frame** → elle contient
  l'écran composé (pas la RenderTexture). Le script doit **terminer** (`graphics.quit()`
  après la capture) sinon la boucle tourne à l'infini sous Xvfb.
- Inspecter les pixels (pas de PIL/imagemagick) : via chromium (voir B) sur `file://…png`
  → `drawImage` + `getImageData` (centroïde, bbox, couleur d'un pixel).

### B. Web / WASM via Playwright (chromium)
- `playwright` est installé par le hook de session, **en GLOBAL** (`npm install -g`), et
  chromium est dans `/opt/pw-browsers/`. Il n'y a PAS de `node_modules` à la racine du dépôt :
  node ne résout pas les modules globaux depuis un dossier quelconque, donc
  `require('playwright')` échoue avec « Cannot find module ». **Lancer avec
  `NODE_PATH=$(npm root -g) node script.js`** — et ne jamais conclure que playwright est
  absent sur ce seul message (vérifier `npm ls -g --depth=0`).
- Le message « Failed to install browsers » du démarrage de session vient du
  `playwright install --with-deps` (apt bloqué par le proxy sur les PPA) : le paquet npm et le
  navigateur, eux, sont bien là.
- `chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox'] })`
  suffit (pas de GPU dans le conteneur, WebGL2 en logiciel).
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

## Conventions de nommage

| Surface | Convention | Exemples |
|---|---|---|
| **API Ollin** (fonctions/méthodes de modules exposées aux scripts) | **camelCase** | `beginDraw`, `strokeSize`, `setPos`, `noiseSeed`, `getPixel` |
| **API Ollin** (constructeurs / classes) | **PascalCase** | `Color`, `Quat`, `Camera`, `Light` |
| **Interne C++** (fonctions, méthodes, helpers, statiques, variables) | **snake_case**, préfixe module quand pertinent | `gfx_begin3d`, `cam_set_pos`, `math_rand`, `make_builtin`, `map_set`, `alloc_reg` |
| **Interne C++** (statiques de fichier) | préfixe `s_` + snake | `s_target`, `s_run_active` |
| **Interne C++** (types / classes) | **PascalCase** | `Value`, `Chunk`, `Frame` |

- **Règle stricte, côté API Ollin : jamais de `snake_case`.** Le nom exposé (1ᵉʳ argument de `map_set(..., make_builtin(...))`) peut différer du nom C++ interne (ex. exposé `setPos` ↔ interne `cam_set_pos`). Les méta-méthodes (`__str`, `__add`, `init`, clés `__class__`/`__name__`) sont exemptées.
- **Règle stricte, côté C++ interne : `snake_case` partout.** Une seule convention pour tout le code du moteur (choix de cohérence interne, indépendant de l'API langage). Le C++ « parle la même langue » que la STL qu'il appelle. **Exceptions** (axes orthogonaux, pas des choix de casse) : types/classes en `PascalCase`, statiques préfixés `s_`, méta-noms `__…` du langage, et **identifiants externes conservés tels quels** — API raylib/rlgl (`rl*`/`gl*`), méthodes `emscripten::val` (`isNumber`, `isNull`…), champs de structs raylib (`vaoId`, `texId`, `meshMaterial`…). Les noms d'API exposés et les identifiants GLSL des shaders vivent dans des **littéraux de chaîne** → hors casse C++. **Les blocs `EM_ASM({…})` sont du JavaScript stringifié par la macro (PAS un littéral de chaîne)** : leurs identifiants JS (`getElementById`, `srcObject`, `createElement`…) restent en camelCase et sont neutralisés par span équilibré (comme dans `check_naming.sh`) — un renommage naïf par mot les casserait.
- **Garde-fou** : `tests/check_naming.sh` (inclus dans `tests/run.sh`) vérifie les **deux sens** — (1) aucun builtin exposé ne contient de `_` ; (2) aucun identifiant camelCase dans le **code** C++ (chaînes/commentaires ignorés), hors liste blanche externe (`rl*`/`gl*`, méthodes `emscripten::val`, champs raylib). Un nouvel identifiant camelCase interne fait échouer le test.
- **Code utilisateur** (`.ol`) : aucune contrainte imposée par le langage (le nommage des variables/fonctions de l'utilisateur est libre).

## Commentaires (règle générale — moteur C++ ET code Ollin)

**Minimiser les commentaires : le code doit s'auto-documenter** (noms explicites, petites
fonctions, découpage clair) plutôt que d'être paraphrasé.

- **Garder** uniquement les commentaires à valeur ajoutée : le **pourquoi** — intention,
  invariant, piège non évident, décision/contrainte, ordre requis, référence.
- **Supprimer le bruit** : commentaire qui répète ce que le code dit déjà (le *quoi*),
  redite du nom d'une fonction/variable, évidence, commentaire périmé, séparateurs décoratifs.
- S'applique à **tout code écrit ou édité** (C++ du moteur comme `.ol`). Ne pas ré-ajouter de
  bruit lors d'une modification. Cette règle prime sur le style verbeux hérité.

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

**Destructuration multi-retour : UN seul chemin, deux appelants.** `var a, b = f()` (`visit(VarDeclStmt)`) et `a, b = f()` (`visit(MultiAssignStmt)`) émettent la même séquence — appel compilé à une base connue, `MOVE_RESULTS` si l'appel a produit ses valeurs ailleurs, puis `SPREAD_RESULTS`. La réaffectation ne l'avait pas : elle ne comptait qu'une valeur et les cibles suivantes lisaient les temporaires voisins, donc des valeurs décalées (`a, b, c = f()` donnait `1, 1, 2` pour un retour `1, 2, 3`). Toute nouvelle forme de cible doit passer par ce chemin, pas le réinventer.
| SEAL_ENUM     | A      | A=map                      | `R[A].kind = ENUM` — la map devient constante (cf. « Type enum ») |
| CLOSE_UPVALS  | A      | A=premier registre          | ferme les upvalues ouvertes dont `reg_idx >= A` (fin d'itération de boucle) |
| HALT          | —      |                            | arrêt                                            |

## Module `ui` (implémentation)

> API : voir le tutoriel (`docs/views/tutoriel.html`, section « Module ui »).

Widgets dessinés par le moteur, en pile dans le coin haut droit. Trois points
d'accroche dans la boucle de rendu (`graphics_module.cpp`, `run_user_callbacks`) :

- **`ui_poll()` AVANT `mouse_poll(...)`** : il renvoie true s'il a consommé le clic, et
  `mouse_poll(click_taken)` neutralise alors `pressed`/`released`/`doubleClicked`. C'est
  LA raison d'être d'un module natif plutôt qu'une classe Ollin : une classe ne peut pas
  s'interposer, elle devrait voler les callbacks du script (cf. l'avertissement en tête
  de `joystick.ol` et de `trackball.ol`, qui réclament trois relais chacun).
- **`ui_draw()` APRÈS `draw()`** et après `end3d_internal()` : dans la même render
  texture, donc capturé par `graphics.screenshot` et posé par-dessus la 3D.
- **`ui_reset()` dans `ollin_run` (wasm_main.cpp), PAS dans `gfx_run`** : les widgets
  sont déclarés au niveau du fichier, donc AVANT `graphics.run` — réinitialiser dans
  `gfx_run` les effaçait tous (constaté). Le reset appartient au démarrage d'un
  PROGRAMME, comme `image_reset`/`camera_reset`.

**Ouverture** : `s_open` est **faux au démarrage** — l'interface se réduit à une poignée
(trois barres tracées à la main : la police par défaut n'a pas de glyphe de menu). Ouverte,
la ligne de tête porte la poignée et le titre du menu affiché ; le même rectangle
(`s_head_box`) sert dans les deux états, d'où un seul test de clic qui bascule `s_open`.
`ui.show` déplie (montrer = rendre visible) ; `ui.open([menu])`/`close`/`toggle` pilotent
explicitement. Quand rien n'est déclaré, `ui_draw` remet `s_head_box` **et** `s_back_box`
à zéro : sinon une zone cliquable subsisterait sans rien d'affiché.

**Arbre de menus et navigation** : widgets et menus sont des `Node` d'une même table
(`s_nodes`), un menu portant la liste ordonnée des slots de son contenu. Un seul menu
est affiché : `s_nav` est la pile de navigation — `s_nav[0]` est le menu global (la
racine implicite par défaut), les suivants la descente. `ui.show` la remet à une seule
entrée, un clic sur un sous-menu empile, la ligne « < » et `ui.back()` dépilent.

- **Identités stables, pas de pointeurs** : un handle côté script est une instance de
  classe native portant `{slot, gen}`. Déclarer un widget depuis un callback fait
  `push_back` sur `s_nodes` → tout pointeur ou référence serait invalidé. `gen` est
  incrémentée à la libération, donc un handle périmé est détecté au lieu de désigner le
  nœud qui a recyclé le slot.
- **`prune_nav()` après toute suppression** : retirer un menu où l'on se trouve
  laisserait la pile pointer sur un nœud libéré → on la tronque au premier ancêtre
  encore vivant.

**Liste** (`ui.list(libellé, source, ref v [, surChange])`) : mono-sélection sur un tableau,
une map ou un enum. La ligne `LIST` montre l'élément retenu ; un clic ouvre la liste, dont
les lignes sont de vrais nœuds `LIST_ITEM` **engendrés à l'ouverture** comme enfants du nœud
`LIST`. Aucune notion de « ligne virtuelle » n'a donc été introduite : `layout`, `ui_draw` et
`ui_poll` traitent ces items comme n'importe quel contenu de menu, et `s_nav` empile le nœud
`LIST` exactement comme un sous-menu. Choisir un item écrit la référence puis **dépile**.
- Règle d'affichage/retour = celle de `for … in` : un tableau donne ses **valeurs**, une map
  ou un enum ses **clés** (`ui_list_items`, dans `ui_module.h` car partagé avec le stub).
- **Ordre figé** : une map n'en a pas. Un enum est trié par **valeur** (donc l'ordre de
  déclaration), une map ordinaire par libellé — sans quoi la liste se réordonnerait d'une
  ouverture à l'autre.
- Les items sont **reconstruits** à chaque ouverture (la source a pu changer), les anciens
  libérés — sinon ils s'accumuleraient. Les libellés (`value_to_string`, qui peut appeler la
  méta-méthode `__str`) sont calculés **avant** toute allocation, et `open_list` revérifie
  `node_alive` ensuite : ce code Ollin peut avoir appelé `ui.clear`.
- `element.open()` accepte un menu **ou** une liste (`handle_slot` puis test du genre) : la
  liste est ainsi pilotable par programme, donc testable sans clic.

**Slider** (`ui.slider(libellé, ref v, min, max [, défaut] [, surChange])`) : les deux
derniers arguments sont reconnus par leur TYPE (nombre = défaut, fonction = rappel), donc
aucun ordre imposé. La variable liée est la **seule source de vérité** — le nœud ne
mémorise pas la valeur courante, il la relit chaque frame, si bien qu'une écriture du
script déplace la glissière. Une variable `nil` est initialisée à la déclaration
(`ui_slider_init`, partagé avec le stub). Le slider est **entier** seulement si les bornes
ET la valeur de départ le sont : sinon un slider `0..1` arrondirait à 0 ou 1. Le
glissement dure plusieurs frames → `s_drag` retient le nœud par identité `{slot, gen}`,
et `ui_poll` renvoie true tant qu'on glisse (sinon le relâchement atteindrait la scène).

**Style** : toute l'apparence (couleurs, arrondi, épaisseurs, proportions) vit dans le
seul bloc `struct Style` / `const STYLE` de `ui_module.cpp`, et les tailles sont des
fractions de `gfx_logical_height()`. Les lignes sont des rectangles **arrondis sans
contour** — la séparation vient de l'espacement, pas d'un liseré. Le rendu ne lit **aucune** valeur d'apparence en dur : changer le
style est donc une édition locale qui s'applique à tous les widgets. `metrics()` dérive
les dimensions de `STYLE` à chaque frame ; `row_height()` donne sa hauteur propre au
slider (libellé + glissière).

Autres points :
- La géométrie de chaque ligne est celle **de la dernière frame dessinée**, mémorisée
  dans `Node::box` : la zone cliquable est exactement ce qui est affiché.
- Mise en page **proportionnelle** à `gfx_logical_height()` (comme `joystick.ol`) : le
  canvas est en pixels physiques, donc des tailles fixes seraient illisibles sur mobile.
- La pile démarre à la marge haute : l'overlay mémoire/FPS a été déplacé dans le coin
  **bas** droit (`draw_fps_overlay`), donc plus rien à réserver — `gfx_overlay_height()`
  a disparu avec son unique appelant.
- Les libellés s'écrivent avec la police PAR DÉFAUT du moteur (`engine_font_default()`),
  jamais celle que le script a choisie : l'interface garde son apparence quoi que fasse
  le programme. Voir « Polices du moteur ».
- La validation des arguments vit dans `ui_module.h` (`ui_check_*_args`), appelée par le
  module ET par `ui_stub.cpp` : une faute d'appel se voit en natif headless, où tournent
  les tests. Le stub renvoie un **handle inerte** portant les mêmes méthodes, pour qu'un
  script chaînant `ui.menu("x").button(...)` tourne aussi sans graphisme.

## Module `tween` (implémentation)

> API : voir le tutoriel (`docs/views/tutoriel.html`, section « Module tween »).

Anime un champ d'objet (ou une variable passée par `ref`) de sa valeur courante vers une
cible, sur une durée, selon une courbe. **Aucune dépendance raylib** → un seul fichier, pas
de stub, et le module tourne à l'identique en natif headless (où les tests le pilotent).

- **Deux points d'accroche** : `tween_update_all(s_frame_dt)` dans `run_user_callbacks`
  (graphics_module.cpp) **avant** `call_update_if_any()` — `update()` comme `draw()` voient
  donc les valeurs de la frame courante ; `tween_reset()` dans `ollin_run` (wasm_main.cpp)
  à côté de `ui_reset`, sans quoi un tween du programme précédent retiendrait ses objets.
- **Pourquoi natif** : un tween doit avancer à chaque frame ; en bibliothèque Ollin, l'oubli
  d'un `update` dans `draw()` serait le premier bug. `tween_update_all` pose
  `s_engine_driven`, ce qui rend `tween.update` **no-op** côté script — un appel resté dans
  `draw()` doublerait sinon la vitesse.
- **Canal** = UN champ numérique animé (`{holder, ref, key, from, to, integral}`). Une cible
  structurée (instance de classe : `Color`, un `Vec2` utilisateur) est éclatée en un canal
  par composante commune aux deux instances, si bien que l'avancement ne connaît **que des
  nombres** — aucun type n'est câblé dans le module. Le tween écrit **dans** l'instance
  cible, il ne la remplace pas (pas d'allocation par frame).
- **Valeur de départ lue au DÉMARRAGE** (drapeau `started`), pas à la déclaration : avec un
  `delay`, l'animation part de la valeur qu'a le champ à l'échéance.
- **Écrasement** : un nouveau tween annule les canaux existants visant le même
  `(holder, key)` — l'identité de l'objet est celle du `Map*`. Deux `ref` distincts sur la
  même variable ne sont **pas** reconnus comme identiques (deux maps différentes) : limite
  assumée, documentée dans le tutoriel.
- **Réentrance** — mêmes règles que `ui`, pour la même raison (un rappel peut déclarer un
  tween, donc faire `push_back` sur `s_tweens`) : identités `{slot, gen}` au lieu de
  pointeurs, itération par index, **aucune** référence conservée à travers un appel Ollin
  (les canaux **et la courbe** sont copiés avant les écritures, qui exécutent le setter
  d'une `ref` ou une courbe du script), et rappels de fin **collectés puis appelés après la
  passe**. Un tween né PENDANT une passe (`born_pass == s_pass`) n'y est pas avancé : il
  consommerait un pas de temps antérieur à sa naissance, et le résultat dépendait sinon du
  slot obtenu — au-dessus de l'index courant il était avancé, sur un slot recyclé non.
- `free_tween` vide les canaux et relâche `curve_fn`/`on_done` : sinon le module garderait
  l'objet animé vivant longtemps après la fin de l'animation.
- À la fin, la cible **exacte** est écrite : une courbe à dépassement (`back`, `elastic`) ne
  rend pas 1 en 1, et un arrondi laisserait 0,999.
- Les 18 courbes sont un tableau `{nom, fonction}` : les noms exposés vivent dans des
  littéraux de chaîne (donc camelCase), les fonctions C++ sont en `snake_case`.
- **Hors périmètre** (à demander explicitement) : séquences (`then`, boucles, aller-retour),
  chemins/splines, vitesse globale.

## Polices du moteur (`engine_font.h`)

Registre de polices **embarquées**, désignées par un nom : `"sans"` (Liberation Sans,
défaut), `"mono"` (Liberation Mono) et `"pixel"` (la police intégrée de raylib, sans
atlas). Aucun fichier à trouver à l'exécution, aucune option de build → même rendu sur
toutes les cibles, WASM compris (+70 Ko sur le `.wasm` pour les deux atlas).

- Les atlas `src/modules/font_sans.h` / `font_mono.h` sont **générés** par
  `ExportFontAsCode` (raylib) via `tools/gen_ui_font.cpp` — lancé à la main, PAS par le
  build : `xvfb-run -a gen_ui_font <police.ttf> <taille> <nom>` (mode d'emploi complet en
  tête de l'outil). 32 px, ASCII + accents français, SIL OFL 1.1.
- `engine_font(idx)` charge l'atlas au PREMIER usage : le construire crée une texture,
  donc exige un contexte graphique, absent quand les widgets sont déclarés. Repli sur
  `GetFontDefault()` en cas d'échec. Filtre BILINEAR, l'atlas étant le plus souvent réduit.
- `engine_font_reset()` (appelé dans `ollin_run`, comme `ui_reset`) oublie les polices
  **sans les décharger** : leurs textures appartiennent au contexte du programme
  précédent, déjà détruit.
- Côté langage, la police est un **état de style** comme `fontSize` : `s_font_idx` est
  sauvegardé par `capture_style`/`restore_style` et remis au défaut par `reset_styles`.
  `graphics.font([nom])` le pilote et renvoie le nom courant ; `graphics.textSize(texte)`
  mesure avec la police ET la taille courantes (deux valeurs, via `ctx.set_result`).
- `tests/check_naming.sh` **exclut** `font_sans.h`/`font_mono.h` : les identifiants d'un
  fichier généré sont ceux de l'outil, et une correction serait effacée à la génération
  suivante.

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
- **Canvas implicite** : `VM::runEntryHooks()` — si un `draw()` existe et que `graphics` est un module (pas le stub), mais que `graphics.canvas()` n'a **pas** été appelé (drapeau `VM::gfxCanvasCreated()`, posé par `gfx_canvas` via `markGfxCanvas()`), le moteur appelle `graphics.canvas(W, H)` → une session graphique démarre sur la seule présence de `draw()`. **Fait APRÈS `setup()`** : `setup()` est un endroit courant pour appeler `canvas()` soi-même ; le créer avant provoquerait un **double `InitWindow`** (crash « memory access out of bounds » en WASM). Le drapeau vit sur le VM (neuf à chaque run playground) → détection fiable même avec le contexte WebGL réutilisé.

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
- **Test alpha sur le chemin d'atlas** (`if (texel.a < 0.5) discard;`) : un trou de la TUILE perce le cube, ce qui permet un feuillage ajouré sans retirer un seul cube (`voxel_world.ol`, paramètre `trous` de `putTile`). Franc et non fondu, donc **indépendant de l'ordre de dessin** : les cubes restent dans le groupe opaque, rien à trier. Limité au chemin d'atlas (`fragTile.x >= 0`) — une texture semi-transparente posée sur un modèle garde son fondu, et l'eau n'est pas concernée (sa transparence vient de la couleur d'instance, pas de la texture).
- **Dessus déformé (`graphics.corners(a,b,c,d)`)** : un **4ᵉ attribut d'instance** `instanceCorner` (vec4, VBO `vbo_k` pour les chunks / `s_inst_vbo_corner` pour l'immédiat) porte les hauteurs des 4 coins du dessus, en unités LOCALES. Le vertex shader déplace les sommets tels que `vertexPosition.y > 0` de l'interpolation bilinéaire des 4 coins — exacte aux coins (sommets du mesh unitaire à ±0,5) — et recalcule la normale de la seule face du dessus (`vertexNormal.y > 0.5`) depuis les pentes, sinon le relief resterait plat à l'œil. Les sommets hauts des faces latérales suivent la même valeur ⇒ pas de fissure. Défaut `(0,0,0,0)` ⇒ rendu inchangé pour tous les autres appels ; **aucun draw call de plus**. `s_cur_corner` est un état comme `s_cur_tile`, remis à zéro par `reset3d_frame_state`.
- **Tuile animée** : `graphics.tileAnim(t)` désigne une tuile dont l'UV défile (`uniform uTime` = `GetTime()`, `uniform animTile`) → eau qui ondule sans recuire les chunks.
- **Transparence (eau)** : à l'enregistrement, `endChunk` **scinde** les instances en 2 groupes selon l'alpha de la couleur d'instance (`col.a < 250` → groupe transparent) et renvoie `{id, idw, count, wcount}`. Chaque groupe garde son **propre mesh** (`s_rec_mesh` opaque = cube, `s_rec_mesh_w` transparent = **plane** pour l'eau) → l'eau est une **surface plane** au niveau de la mer (`graphics.plane`, une par colonne, jointives = surface continue), PAS une pile de cubes (sinon on verrait les faces internes). `drawChunk` dessine l'opaque (`id`) ; `graphics.drawChunkAlpha(handle)` dessine le transparent (`idw`) en `BLEND_ALPHA` (depth test+write gardés → occlusion propre). **Ordre obligatoire** côté script : TOUT l'opaque (boucle `drawChunk`) PUIS TOUTE l'eau (boucle `drawChunkAlpha`) dans le même `begin3d`. `freeChunk` libère les deux groupes. Les slots de `s_groups` libérés sont **recyclés** via `s_free_groups` (`placeGroup`) → `s_groups` reste borné en streaming infini ; un chunk sans eau ne crée **pas** de groupe transparent (`idw = 0`). `freeGroupById` ne rend un slot au pool que s'il était vivant (double-libération idempotente).
- **Caméra** : classe native `Camera` ; `graphics.camera(...)` renvoie une INSTANCE (`px,py,pz, tx,ty,tz, fovy`). Méthodes : `set_pos`, `look_at`, `move`, `orbit(angle rad, rayon [, hauteur])`. `cameraFromMap()` la relit (up +Y, perspective) ; `s_cam3d` fournit `viewPos` au shader.
- **Profondeur** : la RT raylib porte un depth buffer (desktop + GLES) ; `graphics.clear(couleur opaque)` efface couleur **+ depth** (`rlClearScreenBuffers`).
- **Garde-fou** : `s_in_3d` ; `runUserCallbacks` appelle `end3dInternal()` si `draw()` oublie `end3d` (flush + rééquilibre la pile). `end3d` idempotent.
- **Quaternions** (`graphics_quat.cpp`, math raymath pure, fichier séparé) : classe native `Quat` ; fabriques `graphics.quat()`/`quat_axis(ax,ay,az,deg)`/`quat_euler(pitch,yaw,roll)` (**degrés**) ; méthodes `mul`/`slerp`/`normalize`/`inverse`/`rotate_vec` (renvoient de NOUVELLES instances, valeurs immuables). `graphics.rotateq(q)` (dans graphics3d.cpp) applique `QuaternionToMatrix(q)` via `rlMultMatrixf` (gauche-multiplie comme `rlRotatef` → compose comme `rotate`). `quatFromInstance()`/`makeQuatInstance()` = pont graphics3d↔graphics_quat.
- **Perf/limites** : 1 draw call par `(shape, texture)` — le nombre de **couleurs** n'ajoute pas de draw call (couleur par instance). `cylinder` est **mono-rayon** (`x,y,z,r,h`) : contrainte du mesh unitaire figé. Models externes = extension additive (bucket déjà keyé `(mesh, texture)`).


## Noms exportés par un module (`Stmt::exported_names`)

`import "m" as m` construit `m = {}` puis une entrée par nom déclaré au premier
niveau du module (parser.cpp, `import_stmt`). La liste vient de `collect_top_level_names`,
qui **ne connaît aucune sorte d'instruction** : chaque nœud répond pour lui-même via
`Stmt::exported_names` (ast.h), vide par défaut, redéfini par `VarDeclStmt`,
`FuncDeclStmt`, `ClassDeclStmt` et `EnumDeclStmt` (rien pour `enum a.b`).

**Pourquoi la réponse vit dans le nœud** : la fonction du parser était une cascade de
`dynamic_cast`, donc une nouvelle sorte d'instruction y était ignorée SANS erreur ni
avertissement — `enum` a été livré ainsi, et un module n'exportait pas ses énumérations.
La question est désormais posée à côté de la déclaration du nœud, dans le seul fichier
qu'on édite forcément pour en ajouter une.

**Limite assumée** : le défaut vide n'oblige à rien (une méthode virtuelle pure le
ferait, au prix d'une ligne obligatoire sur les 20 nœuds d'`ast.h`). C'est la proximité
qui protège, pas le compilateur.

## Topologie de l'arbre (`Stmt::for_each_body`)

Même principe pour la DESCENTE : chaque nœud composite déclare ses sous-corps
(`for_each_body`, ast.h) — 9 nœuds, 13 listes d'instructions (un `if` en a trois).
Un parcours combine les deux mécanismes : `accept`/`visit` pour agir SELON la sorte
d'instruction, `for_each_body` pour DESCENDRE.

Deux visiteurs l'utilisent :
- `CollectGlobalsVisitor` : sa méthode `walk` remplace les 8 `visit` qui ne faisaient
  que réénumérer les nœuds composites ; ses `visit` restants ne font plus que collecter.
- `HasFuncQuery` : `stmt_has_func` demande d'abord au nœud s'il PORTE une fonction
  (déclaration, ou lambda dans une de ses propres expressions), puis descend via
  `for_each_body`. Sa descente était tenue à la main et `do … end` y manquait : le
  compilateur croyait qu'aucune closure ne capturait la variable de boucle, recyclait
  les registres, et la closure lisait un registre réutilisé (valeur d'un autre type).
  **Conservatisme inchangé** : `SwitchStmt`, `ClassDeclStmt` et `EnumDeclStmt`
  répondent « oui » sans regarder, ce qui court-circuite la descente — la conversion
  n'autorise donc AUCUNE optimisation nouvelle. Pour `ClassDeclStmt` c'est même la
  réponse EXACTE : une méthode est une fonction et capture par upvalue (vérifié).
  **Affiner `Switch`/`Enum` a été essayé puis abandonné, mesure à l'appui** : le gain est
  nul, car l'aliasage de la variable de boucle est refusé par `loop_body_alias_safe` dès
  qu'une structure est imbriquée, et `body_has_func` ne pilote que `reg_top_` (registres
  réservés), pas la vitesse. Boucle 10M contenant un switch : +0,9 %, sous le bruit de
  disposition du code (±7 %).

**Non converti, volontairement** : `CollectLocalsVisitor`. Il repose sur le fait de NE
PAS descendre (portée lexicale : les locales d'un bloc sont collectées à part, avec leurs
propres registres). Le convertir toucherait l'allocation de registres pour un gain nul.
C'est le SEUL consommateur de l'AST qui garde une liste de sortes d'instructions écrite
à la main, et un oubli y est sans effet : ne pas descendre est justement son but.

**Question distincte, qui n'a PAS migré dans `ast.h`** : le CRITÈRE de noms de
`CollectLocalsVisitor` / `CollectGlobalsVisitor` (`is_global` ou non, classes comprises
ou non). Il dépend du contexte de compilation, donc seule la question « quels noms au
niveau module » vit sur le nœud (`exported_names`) — ne pas confondre les deux en
voulant « généraliser ».

**Filet de sécurité** : `tests/regressions.ol` déclare un `global` au fond de CHAQUE
sorte de construction et le lit depuis une fonction déclarée AVANT — une descente
manquante fait échouer la compilation sur « undeclared variable ». Les 13 listes ont
été cassées une par une pour vérifier que le test les détecte toutes. Un second jeu de
cas pousse une closure sur la variable de boucle depuis un `do`/`if`/`switch`/`try`
imbriqué : une descente manquante y produirait une valeur corrompue.

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

**Portée des variables de boucle** : `var1`/`var2` sont **locales à la boucle** — pas collectées par `collectLocals` ; le compilateur les lie dans `local_regs_` le temps du corps puis **restaure** l'ancienne liaison (ou la supprime) → pas de fuite après la boucle (y référer = « undeclared variable »), une variable externe de même nom est masquée puis restaurée. Recyclage des registres : si `bodyHasFunc(body)` (une closure du corps peut capturer la variable via upvalue ouverte), les registres de boucle restent **réservés** après la sortie pour ne pas être réécrits (closures → valeur finale, cohérent) ; sinon ils sont recyclés. La réserve couvre **aussi les locales du corps** (`keep_captured_regs` garde le plus haut de la réservation de boucle et de celle que `compile_block` a posée) : elles sont capturables comme la variable de boucle, et les redescendre au niveau des seules variables de boucle rendait leur registre aux temporaires — l'appel suivant écrasait alors la valeur sous une upvalue encore ouverte (cas figé dans `regressions.ol`).

**Une variable par ITÉRATION** : quand `body_has_func(body)` est vrai, les deux boucles émettent `CLOSE_UPVALS <premier registre du bloc>` en **deux points** — à l'adresse où reboucle l'itération (donc aussi la cible des `continue`) et à l'adresse de sortie (fin normale, itérateur épuisé, `break`). Fermer une upvalue la fige dans sa valeur et la **retire** de `frame.open_upvals` ; `MAKE_CLOSURE` n'en réutilise donc plus pour ce registre et le tour suivant en crée une neuve → chaque closure garde la valeur de SON tour (modèle Lua 5.4 / `let`). Deux closures d'un même tour continuent de partager la variable (une seule upvalue par registre et par tour). Aucune instruction n'est émise quand le corps ne contient pas de fonction, donc **aucun** coût pour les boucles ordinaires. `close_upvals()` (tout le frame, chemin CHAUD des retours) et `close_upvals_above(seuil)` restent **deux fonctions distinctes** : les fondre grossissait le code de `RETURN` et coûtait 5 % sur `bench_fib` (30 M de retours), mesuré, pour un partage de trois lignes.

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

## Passage par référence (`ref`, implémentation)

> Syntaxe et sémantique : voir `grammar.ebnf` (`refExpr`).

`ref x` est **désucré par le parser** (`parser.cpp`, `ref_expr`) en l'arbre de
`{__ref: true, get: func() return x end, set: func(v) x = v end}`. Conséquence :
**aucun type, aucun opcode, aucune ligne dans `ast.h`, le compilateur ou la VM** — ce
sont les upvalues qui font tout le travail, y compris la capture d'une locale.

- Le paramètre du setter s'appelle `__ref_v` : avec `v`, `ref v` générait
  `func(v) v = v end`, une écriture sans effet (cas figé dans `regressions.ol`).
- Le getter et le setter ont chacun leur propre arbre d'accès (`make_access(n)`) : un
  `unique_ptr` ne se duplique pas.
- `__ref` sert à la VALIDATION côté natif : une map avec `get`/`set` n'est pas forcément
  une référence (le module `data` en a). Helpers `is_ref`/`ref_get`/`ref_set` dans
  `module_utils.h`.
- Cible = nom ou chemin de champs. L'indexation est refusée : le chemin étant réévalué à
  chaque accès, `ref t[i]` suivrait les changements de `i`.
- `ref` est un **mot-clé réservé** : il ne peut plus servir de nom de variable (une
  occurrence de `syntax.ol` a dû être renommée).

## Type enum (implémentation)

> Syntaxe, numérotation et sémantique : voir `grammar.ebnf` (`enumDecl`).

Un enum **est une map** (`T_MAP`), distinguée par `Map::kind == Map::ENUM`. Pas de tag
dédié : en LECTURE (`GET_INDEX`, `MAKE_ITER`, `isFalsy`, `len`, affichage) un enum se
comporte exactement comme une map et **aucun de ces chemins ne connaît les enums**.

- `kind` (uint8_t) loge dans le trou d'alignement après `refcount` → `sizeof(Map)`
  inchangé (80 o, mesuré).
- La garde est dans **`op_SET_INDEX` seul** : toutes les écritures d'un script y passent
  (`E.A = v`, `E[k] = v`, alias, suppression par nil). Le chemin de lecture et son inline
  cache ne paient rien. Coût mesuré sur 5 M d'écritures indexées : +1,4 %, sous la
  sensibilité à la disposition du code (±7 %).
- `Map::set` natif n'est PAS gardé : c'est lui qui construit les modules, et le
  remplissage de l'enum lui-même passe par `SET_INDEX` **avant** le scellement.
- `SEAL_ENUM` est émis en DERNIER par `visit(EnumDeclStmt)` — après le remplissage, dont
  les valeurs peuvent être des appels de fonction.
- `MapPool::acquire`/`release` remettent `kind = PLAIN` : sans ça une map recyclée
  ressortirait gelée (même piège que `version`, cf. invariant ci-dessous).
- Le compilateur tient `enum_names_` (enums sous nom simple) et refuse dès la compilation
  une écriture dont la cible est visiblement l'enum → message nommant l'élément. La VM
  rattrape les chemins indirects avec un message générique.
- Le gel est **superficiel** : un objet/tableau contenu dans l'enum reste modifiable.

**Invariant pools (`MapPool`/`ArrayPool`/`ArrayIteratorPool`) — RÉ-ENTRANCE** : `release()` doit vider (`data.clear()`/`items.clear()`) **AVANT** de tester la capacité `n < CAP`, puis relire `n`. Le clear libère les entrées, et une entrée map/array **ré-entre** le pool (`release` → `buf[n++]`) → `n` peut grandir pendant le clear. Tester `n < CAP` *avant* le clear puis faire `buf[n++]` avec le `n` à jour écrit `buf[CAP]` (= `&n`) et corrompt la free-list (bug du crash au re-run corrigé). Ne jamais remettre le test de capacité avant le clear.

## Accès membre : `GET_INDEX`, pseudo-méthodes et inline cache

**Résolution.** `GET_INDEX` traite quatre familles de receveurs :
- **map / classe** : data PROPRE d'abord, puis la chaîne (`__class__` d'une map, `__parent__` d'une classe) via `proto_chain_rest()` — séparé de `proto_chain_get()` pour ne consulter la data propre qu'**une** fois.
- **chaîne** : membre du module `string` (`string_module_`).
- **tableau** : membre de `array_module_` (`len`, `push`/`enqueue`, `pop`, `dequeue`, `insert`, `delete`, `map`, `filter`, `reduce`, `sort`). Un champ absent est une **erreur** (`array has no field '…'`), pas `nil`. Ces maps sont construites **une fois** au démarrage — plus de chaîne de `strcmp` reconstruisant une closure par accès.
- **pseudo-méthode `len` des maps** : un **repli tout-froid** (rien trouvé dans la data propre ni la chaîne) — elle ne peut pas être une simple entrée de map servie par lookup, puisqu'une entrée `len` définie par la map doit toujours gagner. La clé est comparée par **pointeur interné** (`key_sptr == MK().len_.sptr`, comme `__class__`/`__parent__`) → **aucun `strcmp` dans `GET_INDEX`**. C'est une fonction **nommée** (`builtin_map_len`) pour que `CALL_METHOD` la reconnaisse par pointeur et lui injecte la map en `self` (les maps n'injectent pas `self` : sinon `math.noise(x)` recevrait le module).

**Injection de `self` (`CALL_METHOD`)** : instances, chaînes, tableaux → `self` injecté. Maps → **non** (un module ne se reçoit pas), sauf `builtin_map_len`.

**Inline cache monomorphe** (`VM::gicache_`, un slot par instruction, dimensionné sur `ch->code.size()`) : mémorise `{Map*, version, clé internée → emplacement}`. Hit = même map + version inchangée + même clé ⇒ valeur rendue sans lookup.
- La valeur cachée est un **pointeur NON possédant** (`const Value*` via `Map::find_ptr`) : un hit implique une version inchangée, donc la map contient toujours l'entrée et garde la valeur vivante. Posséder une copie retenait l'objet longtemps après sa libération par le script (mesuré : ×2 sur l'empreinte avec un gros tableau).
- **Copier avant d'écrire** : `Value tmp = *c.val;` puis `regs[base+A] = std::move(tmp)`. Le registre destination peut aliaser l'objet (`m = m.inner`) et détenir sa dernière référence : `regs[A] = *c.val` libérerait la map avant de lire l'union source (`operator=` retient puis relâche, mais lit après). Bloc fermé **avant** `NEXT()` (règle computed-goto).
- **Ne cache que les hits sur la data PROPRE** de l'objet : la validité ne dépend alors que de `(mptr, version)`, y compris pour une instance. Les résolutions **via la chaîne** ne sont pas cachées (muter la classe ne bump pas la version de l'instance). Ne **jamais** conditionner le remplissage par `is_instance()` : ce test fait un lookup `__class__`, donc un coût par accès (régression mesurée).
- `Map::version` = `++g_map_epoch` (époque globale monotone) à chaque `Map::set` **et** au recyclage dans `MapPool::release` → insensible à la réutilisation d'adresse.
- `module_member()` (vm.h) applique le même cache aux maps de module **immuables** (`string_module_`, `array_module_`) → hit systématique après le premier passage.
- **Piège d'aliasing** : le registre destination peut aliaser celui de l'objet (`A==B`) ou de la clé (`A==C`). Capturer `obj.mptr` / `key.sptr` **avant** toute écriture de `regs[base+A]` — les lire après donne la valeur écrasée (le cache ne se remplissait jamais).

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

## Builtins : convention de retour (modèle Lua)

Signature : `using BuiltinFn = int (*)(CallCtx&)`. Comme une `lua_CFunction`, un
builtin **écrit ses valeurs de retour dans les slots résultat** puis **renvoie
leur nombre** (repris dans `last_results_`). Les slots résultat sont
`ctx.args[0..]`, c'est-à-dire les registres à partir du call_base — là où
`RETURN_V` place déjà les retours d'une fonction du langage. Un builtin écrase
donc ses propres arguments (déjà lus), exactement comme `RETURN_V`.

- `ctx.ret(v)` : écrit `v` dans le slot 0 et renvoie 1 (cas courant : une valeur).
- `ctx.setResult(i, v)` : écrit la i-ème valeur (suivi de `return n;`).
- `ctx.result_cap` : nombre de slots **sûrs** (= `reg_count` du frame − A). Toute
  écriture est bornée à cette capacité → aucun débordement hors du frame.

**Invariant registre (sûreté mémoire)** : chaque frame pose
`varargs_base = reg_base + reg_count` et `regs` est dimensionné à
`≥ reg_base + reg_count` ; d'où `result_cap = frame.varargs_base − reg_base − A`.
Le compilateur force `reg_count ≥ call_base + n` pour une destructuration à `n`
cibles (compiler.cpp), donc `result_cap ≥ n` : un builtin peut toujours remplir
les cibles, et les valeurs excédentaires tombent dans les temporaires du frame
(ignorées, jamais au-delà de `varargs_base`). **Le frame top-level doit initialiser
`varargs_base = top_reg_count`** (sinon `result_cap ≤ 0` et `ctx.ret` n'écrit rien).

Les 6 sites d'appel builtin (vm.cpp : `CALL_DYN`, `CALL_METHOD`, `invokeStr`,
init ctor, hook `run`, `callValue`) fixent `result_cap` puis `last_results_ = fn(ctx)`.

**Sens inverse (natif→Ollin), multi-retour** : `VM::callValue` (utilisé par les
builtins d'ordre supérieur — `array.map/filter/reduce`, `mouse`/`keyboard`, …)
rappelle une fonction Ollin mais ne renvoie qu'**une** valeur (`regs[call_base]`).
Pour récupérer plusieurs retours (ex. `image.mapPixel` dont le callback renvoie
`r,g,b,a`), utiliser `VM::callValueMulti(fn, args, argc, out, out_cap) → n` : après
`runGoto`, les valeurs de retour sont déjà en `regs[call_base..]` et `last_results_`
en donne le compte ; la méthode en recopie `min(last_results_, out_cap)` dans `out`
avant de rétrécir `regs`. Aucun mécanisme moteur nouveau — seulement la lecture des
valeurs déjà produites.
