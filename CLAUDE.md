# Ollin — Scripting Language
> Minimaliste · Expressif · Dynamiquement typé · Compilé · Embarquable

## Collaboration

**Langue et format de réponse (règle permanente)** : répondre **toujours en
français**. Les rapports, revues de code, synthèses et résultats sont rendus en
**texte lisible** (titres, listes, prose) — **jamais** de JSON brut ni de dump de
structure de données comme livrable à l'utilisateur, même si un outil/skill
produit du JSON en interne (le convertir en rapport lisible avant de le présenter).

**Langue du DÉPÔT : anglais, SANS exception de contenu (règle permanente)**. Tout ce qui est
écrit dans le dépôt est en anglais : identifiants C++ et Ollin, commentaires (en-tête comme
corps), messages d'erreur du moteur, textes affichés par la web app et par les exemples, prose
du tutoriel, libellés des données, messages des scripts de test et d'outillage. Un identifiant
ne mélange JAMAIS les deux langues (`voice_sonne`, `leves_masque` étaient des fautes).
Le français ne subsiste que dans **nos échanges** — mes réponses à l'utilisateur (cf. ci-dessus)
— et dans les fichiers qui PORTENT ces échanges : **CLAUDE.md** et `.claude/` (consignes,
skills, hooks). Il n'y a plus de frontière « ce qui s'adresse au lecteur francophone » : la
documentation destinée à l'utilisateur d'Ollin est en anglais comme le reste.
Cette frontière est **ARRÊTÉE** : ne plus proposer de traduire ces deux-là, ni redemander
confirmation.

**Ce qui reste accentué N'EST PAS du français** (vérifié, ne pas « corriger ») : les données
de test UTF-8 (`"café"`, `"ÉÀÙÇ"` dans `tests/regressions.ol` ; `"café"` et `"straße"` dans le
tutoriel), les plages Latin-1 de `string_module.cpp` (`à..þ`), le jeu de caractères de
`tools/gen_ui_font.cpp`, et le code généré ou vendorisé (`font_sans.h`, `font_mono.h`,
`docs/vendor/`, `docs/wasm/`).

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

**Une revue se CORRIGE (règle permanente)** : tout constat produit par une revue de code
— `/code-review`, `/simplify`, ou une relecture demandée en clair — est corrigé dans le même
tour, sans demander confirmation. La question « veux-tu que je corrige ? » est proscrite : la
réponse est toujours oui. Seule exception, à énoncer en une ligne : un constat dont la
correction changerait un comportement voulu ou déborderait largement du périmètre revu.

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
├── bench/             benchmarks (.ol / .lua / .py) + icount.sh (compte d'instructions)
└── docs/              tutoriel, playground, samples, wasm
```

## Web app monopage (docs/)

Le site (`docs/`) est une **SPA** : une seule page hôte, plusieurs vues montées à la demande.

- `docs/index.html` — **shell** minimal : `#view` (point de montage) + `<canvas id="canvas">` partagé (rangé dans `#canvas-home` hors exécution) ; charge `app.js`.
- `docs/app.js` — **routeur** par hash. `#/<vue>[/<ancre>]` change de vue ; `#<ancre>` (sans `/`) = ancre interne de la vue courante (défilement, pas de re-montage). `ctx.anchor` = sous-chemin après la vue (ancre tutoriel, ou paramètre de vue). Charge le runtime **WASM une seule fois** (`getOllin`, instance partagée) et déplace le canvas partagé dans la vue active.
- **Exemples en lecture directe** : `#/playground/sample/<fichier>` (et `#/run/sample/<fichier>`) ouvre un exemple `docs/samples/<fichier>` **depuis le dépôt, sans copie ni persistance** (re-`fetch` frais à chaque chargement → un refresh reprend la version du dépôt). Édition libre non enregistrée ; bouton « Créer un projet » pour forker dans IndexedDB. Les projets utilisateur (IndexedDB) restent le mode par défaut.
- `docs/views/<vue>.html` + `docs/views/<vue>.js` — chaque vue = un fragment (CSS + markup, `<style>` actif seulement monté) + un module `export function init(ctx) → cleanup()`. `ctx = { root, getOllin, hardReload, navigate }`. Vues : `tutoriel`, `playground`, `run`, `perf`.
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

**Contraste (règle permanente)** : la palette des vues est tenue à des seuils mesurés, pas à
l'œil. Texte courant ≥ 7:1, texte atténué et libellé de bouton ≥ 4,5:1 sur **chacun** des trois
fonds (`--bg`, `--surface`, `--surface2`), contour d'un élément interactif ≥ 3:1. D'où **deux**
jetons de trait, à ne pas confondre : `--border` ne fait que séparer des zones (décoratif, ~1,6:1)
tandis que `--border-strong` identifie un bouton, un champ ou un sélecteur — les fondre rendait un
bouton indiscernable de son fond (1,3:1, constaté). Un fond accentué porte l'encre SOMBRE
(`--accent-ink`) : l'accent étant clair pour ressortir du fond, du blanc dessus ne donnait que
2,4:1. Toute nouvelle couleur se vérifie par le calcul WCAG avant d'être posée.

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
| `tests/syntax.ol` | Claude | **la FORME** : toute construction du langage y figure, avec l'assertion minimale qui montre qu'elle s'écrit et fonctionne |
| `tests/regressions.ol` | Claude | **le COMPORTEMENT** : sémantique fine, cas limites, combinaisons et pièges d'implémentation (variable par itération, registres recyclés sous une upvalue ouverte, descente d'arbre manquante, réentrance…) |
| `tests/test_errors.sh` | Claude | **l'ÉCHEC** : tout ce que le moteur doit REFUSER, et le message qu'il rend |
| `tests/check_grammar_coverage.sh` | Claude | **garde-fou de couverture** : chaque règle de `grammar.ebnf` doit être citée par une étiquette `## [grammar: …]` de `syntax.ol` |
| `docs/grammar.ebnf` | Claude | **grammaire formelle = référence de la syntaxe du langage** (dérivée de `syntax.ol`) |
| `docs/views/tutoriel.html` | Claude | tutoriel HTML (vue de la web app monopage) |
| `docs/views/perf.html` + `perf.js` | Claude | vue `#/perf` : rapport de performances du moteur — le TRAVAIL (`docs/data/icount-history.json`, série historique) et le TEMPS (`docs/data/bench-snapshot.json`, relevé unique) |
| `tools/ollin-vscode/` | Claude | extension VS Code (colorisation) |

**Règle** : toute évolution de la syntaxe doit mettre à jour simultanément `grammar.ebnf` (référence), `tests/syntax.ol` (qui doit EXERCER la forme nouvelle, pas seulement la mentionner), `docs/views/tutoriel.html` et `tools/ollin-vscode/`. **Répartition des tests, sans recouvrement** : la FORME dans `tests/syntax.ol` (une construction du langage y figure toujours — une forme couverte seulement ailleurs est un manque), le COMPORTEMENT dans `tests/regressions.ol` (sémantique fine, cas limites, ce qui a déjà été cassé), l'ÉCHEC dans `tests/test_errors.sh` (ce qui doit être refusé, et avec quel message) — un échec RATTRAPÉ par `try`/`catch` reste du comportement, `test_errors.sh` ne sait vérifier qu'un message rendu sur la sortie d'erreur. Un test de sémantique qui n'exhibe aucune forme nouvelle n'a rien à faire dans `syntax.ol`. **La couverture est vérifiée par `tests/check_grammar_coverage.sh`** (dans `run.sh`) : chaque section de `syntax.ol` porte une étiquette `## [grammar: forStmt, rangeLit]` citant les règles qu'elle exerce, et le script échoue si une règle de `grammar.ebnf` n'est citée nulle part — ou si une étiquette cite un nom qui n'existe pas. Il compare des NOMS, il ne lit pas le code : l'étiquette engage celui qui la pose. Ajouter une règle à la grammaire oblige donc à écrire son test. CLAUDE.md n'est mis à jour que si l'implémentation (opcodes, stratégie de compilation, structures) change.

**Règle (permanente) : exécuter `bash tests/run.sh` avant CHAQUE commit, sans exception.**
Pas seulement après une évolution du moteur (VM, compilateur, modules natifs) : aussi pour un
exemple `.ol`, la web app, un commentaire, la documentation. La suite couvre `syntax.ol`,
`regressions.ol`, `test_errors.sh` et `check_naming.sh`, et dure quelques secondes — juger au
cas par cas qu'un changement « ne peut rien casser » est un pari qui coûte plus cher qu'elle.
Un commit ne part que sur un « ALL GREEN ».

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

**Publication des résultats (vue `#/perf`)** : les temps vont dans `docs/data/bench-snapshot.json`,
qui est **remplacé** à chaque relevé, jamais complété — un temps ne valant que pour une machine
et un moment, une série historique de temps n'aurait aucun sens (`icount-history.json`, lui,
s'allonge). Le fichier porte donc date, commit, machine, build et nombre d'exécutions, et la vue
les affiche : un relevé sans son contexte serait trompeur. La vue reste valide sans ce fichier
(sa section disparaît).

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
- **Conteneur distant** : `lua5.4` est installé par `.claude/hooks/session-start.sh` (paquet apt), Python y est déjà. L'image ne fournit pas toujours Lua et le conteneur est recréé à chaque reprise — si `lua5.4` manque malgré tout, `sudo apt-get install -y lua5.4` suffit ; **ne pas compiler Lua depuis les sources** (perte de temps, et `lua.org` est bloqué par le proxy).
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
- **« C'est la disposition du code » ne s'AFFIRME pas, ça se MESURE : `bash bench/icount.sh
  [<réf>] [<réf>]`.** Le script compte les instructions exécutées (callgrind), chiffre
  déterministe et indifférent à l'adresse du code comme au cache : il mesure le TRAVAIL.
  Instructions en hausse = coût réel à corriger ; instructions stables et temps qui bouge =
  placement, et il n'y a rien à optimiser. Sa sensibilité est vérifiée (+0,61 % pour quatre
  comparaisons ajoutées à `op_ADD`), donc un 0,00 % n'est pas un outil aveugle.
  Ne jamais invoquer la disposition sans avoir lancé ce script.
- **Une mesure de dérive ne vaut que sur les commits qui touchent le MOTEUR** (`vm.cpp`,
  `value.h`, `compiler.cpp`, `opcode.h`, `vm.h`, `collections/`). Les jalonner par « les N
  derniers commits » ne prouve rien : la plupart portent sur les tests, la web app ou les
  exemples, et un compte d'instructions y est stable par construction. `git log -- src/vm.cpp
  src/value.h src/compiler.cpp src/opcode.h src/vm.h src/collections/` donne les bons jalons.
  ⚠ Le conteneur distant part d'un **clone superficiel** (`.git/shallow`, ~60 commits) :
  `git fetch --unshallow origin` est nécessaire avant toute mesure d'histoire, sinon
  l'historique du moteur paraît ne compter que trois ou quatre commits.
- **Ce que la dérive vaut réellement — mesuré sur les 34 journées de commits moteur du
  20/06 au 18/08** (une journée sur deux mois entiers, `bench/icount.sh`) :

  | | 20/06 | 18/08 | bilan |
  |---|---|---|---|
  | `fib` | 121 470 752 | 97 753 231 | **−19,5 %** |
  | boucle | 112 555 011 | 32 603 058 | **−71,0 %** (÷3,4) |
  | map | 101 653 234 | 52 997 247 | **−47,9 %** (÷1,9) |

  Le travail bouge dans les DEUX sens, et fortement : il faut le mesurer, jamais le
  supposer. Hausses réelles constatées — +9,4 % (`switch`), +7,7 % (suppression de
  `T_MODULE`), +4,6 % (globales `W`/`H`), +1,8 % (expansion de `...`, `CW`/`CH`), +0,6 %
  (inline cache, variable par itération). Gains — **−67 % sur la boucle** (chemin rapide
  `FOR_PREP`/`FOR_LOOP` + compteur de tours), −35 % sur la map (`StringTable` robin_hood),
  −8 % sur `fib` (clés calculées), −5,5 % (clé `len` par pointeur). Il n'y a donc aucune
  dette qui s'accumule, et surtout pas parce que « rien ne bouge » : les gains ont
  largement dépassé les coûts.
- **Limite de méthode à énoncer avec tout tableau d'histoire** : un jalon par JOURNÉE
  mesure l'état en fin de journée, donc l'écart cumule TOUS les commits du jour et le sujet
  affiché (le dernier) n'en porte ni le mérite ni le blâme. Exemple vérifié : le −67 % de la
  boucle apparaît sous « renuméroter les tags », un commit de 34 lignes dans `value.h` qui
  annonçait « loop neutre » — l'intervalle contenait quatorze commits, dont le chemin rapide
  du `for` numérique. Attribuer un écart à un commit précis demande de mesurer CE commit.
- **Jusqu'où on peut remonter (sondé)** : le dépôt part du 12/06/2026, mais la borne n'est
  pas git — c'est le LANGAGE. Au 12/06 la cible s'appelle `tau` (renommage ultérieur) et
  refuse `<=`, `for i = 1, n` et les maps ; du 13 au 18/06 seul `fib` s'exécute ; **à partir
  du 20/06 les trois scripts passent**. Le 19/06 part en *segmentation fault* sur `fib`, et
  le 25/06 ne compile pas : deux trous inévitables dans une série qui traverse ces dates.

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

Widgets dessinés par le moteur, en pile dans le coin haut droit. Le moteur appelle le
module en trois endroits de sa boucle de rendu (`graphics_module.cpp`, `run_user_callbacks`) :

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

## Module `touch` (multitouche, implémentation)

> API : voir le tutoriel (`docs/views/tutoriel.html`, section « Module touch »).

raylib ne donne qu'une PHOTOGRAPHIE des contacts à chaque image (`GetTouchPointCount`,
`GetTouchPointId`, `GetTouchPosition`) : aucun événement ne dit lequel vient d'apparaître.
Le module garde donc la liste de l'image précédente et la compare — un identifiant nouveau
donne `began`, un identifiant disparu donne `ended` (avec sa DERNIÈRE position, celle du
lever n'étant plus lisible), une position changée donne `moved`. C'est tout le module.

**Sans lui, `mouse` ne peut rapporter qu'un doigt** : dans `rcore_web.c`, la position de la
souris n'est recopiée depuis le tactile que `if (pointCount == 1)`, si bien qu'au second
doigt la souris cesse de suivre quoi que ce soit.

**`mouse.released` est déduit de l'ÉTAT du bouton, pas de l'événement.** `IsMouseButtonReleased`
n'arrive JAMAIS quand l'émulation de la souris cesse en pleine pression — ce que fait le
navigateur dès la pose d'un second doigt (`rcore_web.c` ne recopie la position que
`if (pointCount == 1)`). Un appui restait alors sans relâchement, et tout script tenant un état
« bouton enfoncé » (glisser-déposer, tracé, note tenue) le gardait pour toujours ; l'exemple
sonore portait un relais pour le rattraper, désormais retiré. `mouse_poll` compare donc
`s_down` (le script a reçu un `pressed`) à `IsMouseButtonDown`, ce qui couvre du même coup la
perte de focus et tout autre événement manqué, sans énumérer les causes. `mouse_reset` (appelé
dans `ollin_run`) évite qu'un programme neuf hérite d'un bouton enfoncé.
- ⚠ Ce trou N'EST PAS reproductible au harnais : la souris de Playwright est un vrai événement
  souris, pas l'émulation du navigateur, donc l'événement de relâchement y arrive toujours. Ce
  qui est mesuré est indirect — avec la correction, un appui maintenu puis deux doigts posés
  donnent trois notes (RMS 0,149) contre une seule avant (0,087).

**Les rappels de `mouse` ne sont PAS filtrés** (décision explicite de l'utilisateur) : sur un
doigt unique le système émule la souris, donc les deux familles partent et un script qui
déclare les deux reçoit le geste deux fois. Corollaire pour les exemples : écrire chaque
chemin de façon IDEMPOTENTE — dans `sound_demo.ol`, `suivre()` n'agit que si la touche
survolée a changé, ce qui rend le doublon sans effet.

- Table de taille fixe, 8 contacts (`MAX_TOUCH_POINTS` de raylib) ; un neuvième doigt est
  ignoré, comme raylib l'ignore.
- **`touch.pinch(scale, cx, cy)` est DÉRIVÉ de deux contacts**, calculé dans le moteur et non
  par chaque script : c'est le seul zoom d'un téléphone (`mouse.scrolled` rapporte une molette,
  qu'aucun écran tactile n'a). `scale` est un **rapport entre deux frames**, donc il se compose
  par multiplication et ne laisse aucun état au script. Trois pièges sont réglés une fois pour
  toutes : le geste est identifié par la **paire triée** d'identifiants (la couche graphique peut
  échanger ses deux entrées d'une frame à l'autre, ce qui réarmerait la référence à chaque tour) ;
  remplacer un doigt de la paire **réarme** la distance de référence au lieu d'annoncer un saut ;
  et deux doigts au même point sont écartés (`< 1 px`) au lieu d'être divisés, ce qui rendrait un
  facteur de plusieurs centaines. Des doigts immobiles n'appellent rien. Appelé APRÈS les rappels
  par doigt (un script qui suit ses doigts a déjà mis son état à jour), désarmé par `touch_reset`.
  **Mesuré au navigateur** (événements tactiles synthétiques via CDP) : écartement de ±30 à
  ±120 px → produit des rapports = 4,0000004 (soit exactement 120/30) en 5 appels ; retour à
  ±40 px → 1,3333 ; doigts immobiles, un seul doigt, et échange d'un doigt de la paire → aucun
  appel, donc aucun saut.
- **Un pincement n'est pas un glissement** : sous deux doigts le système émule toujours la souris
  avec l'un d'eux, donc un script qui oriente la scène sur `mouse.moved` doit se garder par
  `touch.count() > 1` — sinon la scène tourne pendant qu'on zoome (`iso_camera.ol` le fait).
- **`touch_begin_frame()` AVANT `mouse_poll`, `touch_poll()` après.** Le relevé des contacts
  est une étape de la frame à part entière, et non le début de `touch_poll` : les rappels de
  `mouse` s'exécutent avant, et beaucoup interrogent `touch.count()` pour savoir si le geste
  vient d'un doigt (le système émule la souris sur un doigt unique). Relever dans `touch_poll`
  rendait cette lecture en retard d'une image — un doigt posé y était vu comme « aucun
  contact », l'émulation de la souris s'attribuait le geste, et l'archet de `sound_demo` ne
  suivait plus le doigt (signalé par l'utilisateur, diagnostiqué en affichant à l'écran la
  valeur que le script voyait).
- ⚠ **Un identifiant de contact peut valoir 0, et `0` est FAUX en Ollin.** Toute variable
  qui retient un identifiant se compare donc à `nil` explicitement, jamais par véracité :
  `sound_demo` testait `if pilote then`, et l'archet restait muet sous le premier doigt du
  navigateur. Corollaire pour les tests : un harnais qui n'emploie que les identifiants 1, 2, 3
  ne peut PAS voir ce défaut — il faut exercer l'identifiant 0.
- `touch_poll()` est appelé APRÈS `mouse_poll` dans `run_user_callbacks` ; `touch_reset()`
  dans `ollin_run`, sinon un doigt resté « posé » ferait croire à un geste en cours.
- La liste de référence est recopiée APRÈS les appels au script : un rappel qui lève laisse
  ainsi un état cohérent.
- Trois arguments passent par la forme générique `call_value(fn, args, argc)` — le VM n'a pas
  de surcharge à trois, et en ajouter une pour un seul appelant ne se justifie pas.
- **La liste de raylib MENT, et le module la filtre.** Deux cas : (1) sur `touchend`, raylib
  ne retire qu'UN contact changé (il sort de sa boucle au premier), alors qu'emscripten lui
  transmet l'UNION de `e.touches` et de `e.changedTouches` — deux doigts levés ensemble
  laissent donc un fantôme ; (2) à la perte de focus, aucun `touchend` n'arrive et tous les
  doigts restent « posés ». Le module écoute donc le navigateur (écouteurs de CAPTURE sur
  `touchstart/move/end/cancel`, plus `blur` et `visibilitychange`).
- **UN relevé par image, UNE traversée de la frontière JavaScript.** `touch_begin_frame` établit la
  liste filtrée de l'image (`s_cur`) ; `count()` et `points()` la relisent. Deux raisons : les
  accesseurs voient exactement ce que les rappels ont vu, et un script qui interroge l'état
  plusieurs fois par image ne paie rien. Le filtre passe les identifiants bruts en un seul
  `EM_ASM_INT` qui rend un **masque de bits** des contacts levés — interroger l'ensemble contact
  par contact coûtait un aller-retour par doigt. Le même passage oublie les identifiants levés
  que raylib ne rapporte plus.
- **SENS DU FILTRE — le navigateur prouve un LEVER, il n'autorise pas une pose.** Ne jamais
  l'inverser. Prendre la liste des doigts posés du DOM pour vérité et n'accepter que ce qu'elle
  contient a été livré une première fois, puis **signalé par l'utilisateur sur un vrai
  téléphone** : des contacts encore appuyés étaient perdus, car tout ce que cette liste ignore
  (événement manqué, identifiant renuméroté, focus rapporté à faux le temps d'une barre
  d'adresse) devenait une annulation. Le module tient donc `__ollinTouchGone`, l'ensemble des
  identifiants dont le lever a été VU, et ne retire que ceux-là ; un identifiant en sort dès
  qu'un doigt se repose avec ce numéro (le navigateur les recycle, sinon le doigt suivant
  naîtrait déjà mort) ou dès que raylib cesse de le rapporter. `__ollinTouchHeld` (miroir de
  `e.touches`) ne sert qu'à alimenter le premier lors d'un `blur`, où aucun `touchend` n'arrive.
  Règle générale : un doute laisse le doigt vivant.
  **`IsWindowFocused()` a été retiré du filtre** : il ne suffisait pas (mesuré — une note tenue
  continuait de sonner après un `blur` avec ce seul test) et il coupait des doigts posés sur un
  vrai appareil. La perte de focus se traite là où elle est certaine, dans l'écouteur `blur`.
  ⚠ Le cas (1) est couvert par CONSTRUCTION, pas par mesure : le harnais de test (événements
  tactiles synthétiques via CDP) ne le reproduit pas, raylib y rendant le même compte que le
  navigateur. Ne pas prétendre l'avoir vérifié. La NON-RÉGRESSION, elle, est mesurée : en
  vidant de force les ensembles côté navigateur pendant qu'un doigt est posé, l'ancien filtre
  faisait tomber le son à zéro (RMS 0,0865 → 0) et le nouveau le tient (0,0872 → 0,0861).
- **Piège d'écriture d'un `EM_ASM`** : c'est une MACRO, donc une virgule HORS parenthèses y
  sépare ses arguments — un littéral de tableau `['a', 'b']` ou d'objet `{a: 1, b: 2}` ne
  compile pas. Écrire `'a b'.split(' ')` et poser les champs un par un.
- Testé au navigateur par `Input.dispatchTouchEvent` (CDP) avec deux points simultanés, dans
  un contexte `hasTouch: true` : deux notes mesurées ensemble (do 262 Hz et sol 392 Hz à
  −45 dB, plancher à −156 dB), et RMS nul après le lever. ⚠ Le spectre de l'`AnalyserNode`
  est LISSÉ dans le temps (0,8 par défaut) et garde une traîne : c'est le RMS temporel qui
  prouve l'extinction.

## Modules `audio` et `sound` (implémentation)

> API : voir le tutoriel (`docs/views/tutoriel.html`, section « Modules audio et sound »).

Le son se partage en deux modules : `audio` est la SESSION (périphérique, volume général,
pause), `sound` est ce qui SONNE — un oscillateur vivant ou un tampon calculé. Deux modules
et non trois : l'oscillateur est une fabrique de `sound` (`sound.osc`), décision prise pour
garder une surface réduite.

**Ni l'un ni l'autre n'est jamais nil**, contrairement à `graphics` : la génération d'ondes
est un pur calcul, donc l'API entière existe dans un build sans raylib, où seule la sortie
devient muette. C'est ce qui rend la synthèse testable dans le conteneur d'intégration, qui
n'a aucun périphérique (`/dev/snd` absent) — sans quoi les tests ne pourraient vérifier que
des refus.

**Découpage des fichiers** (le patron de `graphics_internal.h`) :

| Fichier | Compilé | Rôle |
|---|---|---|
| `audio_module.cpp` / `audio_stub.cpp` | selon raylib | session : ouverture différée, volume, pause |
| `sound_module.cpp` | PARTOUT | API et état : voix, tampons, handles, validation |
| `sound_output.cpp` / `sound_output_stub.cpp` | selon raylib | le flux et le mélangeur |
| `sound_internal.h` | — | frontière : table de voix, table de tampons, compteur de blocs mélangés |
| `sound_env.h` | — | `adsr_level`, en forme fermée (cf. plus bas) |

**Le rappel audio ne contient JAMAIS de code Ollin.** Il a une échéance de quelques
millisecondes, et la manquer s'entend comme un clic. Conséquences, qui expliquent toute
l'architecture : la forme d'un oscillateur est calculée en C++ (le script ne règle que des
nombres), la formule d'un `sound.generate` est échantillonnée UNE fois sur le fil principal,
le rappel n'alloue rien et ne prend aucun verrou, et les paramètres sont des atomiques lus un
par un. Ils sont en **double** et non en float : `0,01` rangé en float remonte à
`0,009999999776` et ne s'égale plus à lui-même, ce qui trahirait un script relisant ce qu'il
a écrit. Vérifié sans verrou sur les deux cibles (`is_always_lock_free`).

**UN SEUL flux pour toutes les voix**, mélangé par nos soins. Le rappel de raylib ne
transporte aucune donnée utilisateur (sa signature n'a que le tampon et le nombre de trames),
donc un flux par voix exigerait autant de fonctions distinctes ; et le mélangeur unique est
l'endroit où vivent la pause globale et les tampons. Tampon de sortie de 1024 trames (~23 ms)
— au navigateur le mélange partage le fil de la VM (le dos-end miniaudio passe par un
`ScriptProcessorNode`, pas un AudioWorklet : celui-ci réclamerait la mémoire partagée, donc
des en-têtes d'isolation que GitHub Pages ne permet pas de poser), si bien qu'une frame très
lourde s'entend.

**Gain lissé sur 5 ms**, par-dessus l'enveloppe : démarrer ou arrêter une onde carrée d'un
coup produit un clic très audible, et une attaque nulle serait un saut.

**Formes à bande limitée (PolyBLEP)** : une dent de scie ou un créneau calculés directement
sautent entre deux échantillons, et ce saut porte des harmoniques au-delà de Nyquist qui se
REPLIENT en raies inharmoniques — un son métallique, faux, et d'autant plus sensible que la
hauteur glisse (les raies repliées descendent quand la note monte). `poly_blep` arrondit chaque
discontinuité sur la durée d'un échantillon : une seule pour la dent de scie, deux pour le
créneau. **Mesuré** au navigateur sur une dent de scie à 3000 Hz (44,1 kHz), niveau des raies
repliées, aucune n'étant un multiple de 3000 :

| | 20 100 Hz | 17 100 Hz | 14 100 Hz | 11 100 Hz | plancher |
|---|---|---|---|---|---|
| naïf | −41,8 dB | −43,6 | −43,6 | −44,3 | −121,6 |
| PolyBLEP | −51,3 dB | −56,1 | −59,8 | −65,1 | −188,6 |

Le fondamental et les harmoniques utiles ne bougent pas (−23,8 → −24,0 dB), et la correction
est d'autant plus forte que la raie repliée est GRAVE, donc audible. **Le triangle est laissé
direct** : il n'a aucun saut, seulement deux ruptures de pente, et ses harmoniques décroissent
en 1/n² au lieu de 1/n — son repliement est vingt décibels plus bas, et le corriger demanderait
un second polynôme (sur la pente) pour un gain inaudible.

**Enveloppe en FORME FERMÉE** (`adsr_level(e, t, hold)`) et non en machine à états. Ce n'est
pas un choix esthétique : la même fonction sert au mélangeur (temps réel) et au façonnage
d'un tampon (hors ligne), si bien qu'un test lisant les échantillons d'un tampon **valide la
courbe que le mélangeur emploie** — le seul moyen de la contrôler sans carte son. Le
relâchement part du niveau atteint AU MOMENT du lâcher, sinon lâcher pendant l'attaque
sauterait au niveau de maintien.

**`free()` rend une voix explicitement** : sans elle, un script ne pouvait pas créer ses
oscillateurs à la demande — `alloc_voice` reprend la voix arrêtée la plus ancienne, donc tout
handle encore détenu risquait de désigner un slot recyclé (l'erreur est signalée, mais le
programme est cassé). D'où le pool pré-alloué que tout script polyphonique devait écrire, et
que `sound_demo.ol` portait (une trentaine de lignes, supprimées). `free` lâche l'enveloppe
comme `release`, marque le slot inutilisé et périme le handle ; le slot n'est réellement
repris qu'à l'extinction, la recherche de slot libre testant désormais aussi le SON
(`voice_sonne`) — couper net produirait un clic et perdrait la queue de note.

**Recyclage des voix** : 16 voix, 32 tampons, tables de taille FIXE (le fil audio les
parcourt pendant que le script en réclame). Quand la table est pleine, la voix arrêtée la
plus ANCIENNE est reprise — « la première arrêtée » martelait toujours la voix 0, si bien
qu'un oscillateur survivait à vingt créations quand son voisin n'en survivait pas à une. Une
voix qui sonne n'est jamais volée, et `gen` détecte un handle périmé.

**Durée de vie des échantillons d'un tampon** : le mélangeur ne les lit que tant que
`playing` est vrai. Réutiliser un slot exige donc de le taire PUIS d'attendre qu'un bloc de
mélange se soit écoulé — un bloc déjà en cours peut avoir lu `playing` avant qu'on l'éteigne.
Le compteur de blocs (`sound_mix_epoch`) est l'unique point de synchronisation, sans verrou ;
sans sortie, il avance à chaque appel puisque personne ne lit.

**Gain de sortie compensé** : la loi de panoramique de raylib n'est pas unitaire au centre
(`volume × 0,5 × c × (3 − c²)` par canal, soit **0,6875** pour un flux centré). Un volume
demandé à 1 sortait donc à 0,687 — constaté par mesure au navigateur, retrouvé dans
`raudio.c`, puis compensé sur le flux (`SetAudioStreamVolume`). Après correction : crête
1,000 et RMS 0,704 pour un sinus à pleine échelle.

**Un contexte SUSPENDU ne se reprend que depuis le gestionnaire du geste** — règle de Safari
sur iOS, et elle condamne `audio_wake`, qui part de la boucle de rendu : son `resume` implicite
est refusé, définitivement. Signalé par l'utilisateur (« après un rechargement le son ne
fonctionne plus », rien ne le ramène sauf fermer l'onglet). D'où `install_gesture_resume`
(`audio_module.cpp`), un écouteur DOM posé UNE fois par `audio_reset` — donc **avant** le
premier geste, puisqu'à l'ouverture du périphérique ce geste serait déjà perdu — et gardé
ensuite : chaque geste retente la reprise, ce qui couvre indifféremment le contexte né
suspendu et l'interruption iOS (appel entrant, retour d'arrière-plan), sans que le moteur ait
à distinguer les deux.
- **MESURÉ dans les deux sens**, en suspendant le contexte de force comme le fait Safari :
  avant, RMS 0 et trois gestes de plus n'y changeaient rien (contexte `suspended`) ; après, le
  premier geste suffit (RMS 0 → 0,0869, `suspended` → `running`).
- ⚠ **Playwright lance Chrome avec `--autoplay-policy=no-user-gesture-required`**, ce qui
  masque TOUT problème de geste : six scénarios de rechargement y passaient au vert alors que
  le bug était réel. Ajouter `--autoplay-policy=document-user-activation-required` pour un
  navigateur fidèle — et savoir que même ainsi, Chrome tolère ce que Safari refuse : la
  reproduction est passée par la suspension forcée du contexte, pas par le rechargement.

**Ouverture différée au premier geste** (`audio_wake`, appelé depuis `run_user_callbacks`) :
le navigateur refuse de sonner avant une interaction. Le clavier passe par
`keyboard_pressed_any()` — la file d'appuis de raylib est CONSOMMÉE par `keyboard_poll`, donc
la relire ailleurs ne rendrait rien. Corollaire pour les exemples : un son demandé dans
`setup()` ne s'entend pas, et le geste qui ouvre le périphérique ne s'entend pas lui-même.

**Notes nommées** : `sound.note("C#4")` par le tempérament égal. Un nom est accepté partout où
une fréquence l'est, grâce au point de passage unique `sound_check_freq`.

**Piège de test au navigateur** : un clic Playwright instantané s'ouvre et se referme dans la
MÊME frame, et raylib, qui scrute l'entrée une fois par frame, ne le voit jamais. Passer
`{delay: 150}`. Le signal se vérifie en branchant un `AnalyserNode` sur
`window.miniaudio.devices[0].scriptNode` (RMS, crête, fréquence dominante).

**Hors périmètre, à demander explicitement** : chargement de fichiers (`sound.load`), effets,
enregistrement, spatialisation, synthèse en temps réel pilotée par une formule Ollin.

## Module `tween` (implémentation)

> API : voir le tutoriel (`docs/views/tutoriel.html`, section « Module tween »).

Anime un champ d'objet (ou une variable passée par `ref`) de sa valeur courante vers une
cible, sur une durée, selon une courbe. **Aucune dépendance raylib** → un seul fichier, pas
de stub, et le module tourne à l'identique en natif headless (où les tests le pilotent).

- **Le moteur appelle le module en deux endroits** : `tween_update_all(s_frame_dt)` dans `run_user_callbacks`
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
- **Plan de lecture (`repeat([occurrences] [, allerRetour])`)** : `Tw::plan` est un vecteur de
  sens (+1 aller, -1 retour), un élément par parcours, et `seg` l'index courant. Le compte
  répète le vecteur, le second paramètre y ajoute son miroir (vecteur renversé, sens
  inversés) ; sans compte, `endless` fait tourner l'index au lieu de terminer. Deux appels
  **composent** — `repeat(2, true)` = `+1 +1 -1 -1`, `repeat(nil, true).repeat(2)` = `+1 -1 +1 -1`.
  Le compte est reconnu par sa POSITION, pas par son type : `true` vaut 1 en Ollin (pas de
  type booléen), donc `repeat(true)` serait indistinguable de `repeat(1)` — d'où le `nil`
  explicite pour « sans fin, avec retour ». UNE seule méthode : ni `yoyo()` ni `loop()`. Un segment de sens -1 interpole
  de `to` vers `from` — les bornes des canaux ne sont JAMAIS relues après le premier
  démarrage, sinon un retour dériverait. Le reliquat de temps passe d'un segment au suivant
  (`elapsed -= dur` dans une boucle `while`), sans quoi une animation courte perdrait une
  fraction de seconde à chaque parcours.
- **Suite d'étapes (`tween.sequence(objet, [étapes])`)** : un tween porte un **vecteur
  d'`Etape`** (canaux, durée, courbe), et `tween.to`/`tween.value` en créent une d'UNE étape —
  tout le module ne connaît donc qu'un seul chemin, une séquence n'étant pas un cas
  particulier. Clés d'étape en anglais : `to`, `delay`, `curve`, `target` ; toute autre est
  refusée avec la liste, sans quoi un `duration` mal choisi serait ignoré en silence. `delay`
  porte les DEUX rôles — durée quand l'étape a `to`, attente sinon (`Etape::attente` retient
  ce choix, car une attente sans canal ne doit pas être prise pour une étape vidée par
  `drop_conflicts`). Le plan de lecture s'applique à la SUITE : un segment de sens -1 rejoue
  les étapes en ordre inverse (`etape_index`), chacune à l'envers.
  Trois pièges éprouvés, tous corrigés : le drapeau de démarrage est **par étape** (global, il
  relisait les bornes en marche arrière et le retour n'allait nulle part) ; une étape franchie
  en un seul pas de temps doit être **démarrée puis posée** à son extrémité (`demarrer_etape`
  + `poser_fin_etape`), sinon ses bornes restent celles lues à la construction ; et la
  dernière étape du dernier segment sort de la boucle **sans soustraire** sa durée — c'est ce
  dépassement qui signifie « terminé », le soustraire faisait réécrire la valeur de départ.
  `progress` intègre le TEMPS des étapes franchies, pas leur nombre : des durées inégales
  donneraient sinon une progression qui saute.
- **Hors périmètre** (à demander explicitement) : `then`, `wait` comme méthode, chemins et
  splines, vitesse globale, délai entre répétitions, rappel par tour.

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
`T_RANGE = 12` — Range* ref-counted avec `{start, end, step, incl_right}` (entiers uniquement).

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

## Type booléen (implémentation)

> Syntaxe et sémantique (étanchéité, « le vide est faux ») : voir `grammar.ebnf` (`BOOL`).

`T_BOOL` est un tag **non ref-compté**, donc placé **avant** le pivot `T_STRING` : rangé
après, `tag < T_STRING` l'aurait cru ref-compté et `retain()` aurait déréférencé un
pointeur bidon. Son ajout a décalé `T_STRING` et les sept types comptés d'un cran — sans
risque, aucun bytecode n'étant sérialisé sur disque.

- **Fabrique explicite** `Value::make_bool(bool)`, et surtout PAS de constructeur
  `Value(bool)` : avec `Value(int64_t)` et `Value(double)` déjà présents, il ferait de
  `Value(0)` un booléen par conversion implicite silencieuse.
- **Producteurs** : `NOT`, `AND`, `OR`, les six comparaisons, les trois sites de
  `negate_result` (RETURN), les littéraux (`BoolExpr`), et les prédicats natifs
  (`math.isNan`/`isInf`, `keyboard.isDown`, `data.has`, `graphics.isOpen`/`isVisible`,
  `camera.isOpen`, `tween.isDone`, champ `enabled` d'une `Light`).
- **Étanchéité tenue en UN point** : `VM::as_double` (vm.h) refuse le booléen comme il
  refuse `nil`. Toute l'arithmétique et toutes les comparaisons d'ordre y passent, donc
  aucun opcode n'a eu à changer.
- **Égalité** : `values_equal` teste les DEUX côtés (`av.is_bool() || bv.is_bool()`).
  N'en tester qu'un laissait `false == false` tomber dans le cas par défaut et répondre
  FAUX — cas réellement rencontré, figé dans `regressions.ol`.
- **Clés de map** : `ValueHash`/`ValueEqual` ont leur cas `T_BOOL`, et le hash est décalé
  d'une constante pour que `true` ne collisionne pas avec l'entier 1. Le couple
  INTEGER/FLOAT reste volontairement confondu ; le booléen, non.
- **`is_falsy`** garde toutes ses règles (« le vide est faux ») et gagne le test booléen
  **en tête** : les comparaisons rendant désormais des booléens, c'est le cas le plus
  fréquent sur le chemin chaud de `JUMP_IF_FALSE`.
- `math.isNan`/`isInf` ont leur propre macro `MATH1_BOOL` : `MATH1` passe par `num_value`,
  qui rendrait un nombre.
- **Hors périmètre, à demander** : conversion `bool(v)` (`not not v` en tient lieu).

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

**Ordre des tags = invariant de perf** : tous les types **non ref-comptés** d'abord (0..5, booléen compris), puis le pivot `T_STRING` et tous les **ref-comptés** contigus (6..12). Ainsi `tag < T_STRING` sépare en **un seul test** les valeurs sans gestion mémoire (nil/int/float/function/builtin/bool) de celles à retain/release (`Value::retain()`/`release()`). Tout nouveau type ref-compté doit être ajouté **après** le pivot, tout type non compté **avant**.

| tag        | valeur (uint8_t) | union actif | plage / note        |
|------------|-----------------|-------------|---------------------|
| T_NIL      | 0               | —           | non ref-compté      |
| T_INTEGER  | 1               | ival (int64_t) | ±2^63            |
| T_FLOAT    | 2               | dval (double) | IEEE 754 double   |
| T_FUNCTION | 3               | ival (int64_t, = func_idx) | index dans chunk.funcs (non compté) |
| T_BUILTIN  | 4               | ival (pointeur natif) | fonction native (non compté) |
| T_BOOL     | 5               | ival (0/1)  | booléen ÉTANCHE, non ref-compté (cf. « Type booléen ») |
| T_STRING   | 6               | sptr (InternedStr*) | **pivot** — ref-counted, str_hash = sptr->hash |
| T_MAP      | 7               | mptr (Map*) | ref-counted     |
| T_ARRAY    | 8               | aptr (Array*) | ref-counted   |
| T_ITERATOR | 9               | iptr (Iterator*) | ref-counted |
| T_CLOSURE  | 10              | cptr (Closure*) | ref-counted, holds func_idx + upvals |
| T_CLASS    | 11              | mptr (Map*) | ref-counted ; même layout que T_MAP, distinct pour CALL_DYN |
| T_RANGE    | 12              | rptr (Range*) | ref-counted ; intervalle entier      |

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
