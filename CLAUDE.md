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

**Comment on VÉRIFIE (méthode arrêtée)** : pas une liste de mots français écrite de mémoire — j'en
ai fait trois, chacune ratant ce que les autres trouvaient. Le contrôle est un **dictionnaire** :
chaque mot de la prose (commentaires et chaînes) est soumis à `aspell --lang en`, et les mots qu'il
refuse sont soumis à `aspell --lang fr`. Refusé par l'anglais ET accepté par le français ⇒ français,
sans que j'aie à devenir la source de vérité. Les identifiants passent par le même filtre, découpés
en mots (`snake_case`, `camelCase`). Il faut écarter à la main une trentaine de jetons de code que le
français accepte par hasard (`px`, `regs`, `dur`, `env`, `frac`…) et quelques mots anglais que le
dictionnaire américain refuse (`initialiser`, `recentre`, `DOM`, `CORS`). Cette passe a trouvé
**une centaine** d'occurrences que mes listes avaient manquées, dont des chaînes affichées à
l'utilisateur.

**Ce qui reste accentué N'EST PAS du français** (vérifié, ne pas « corriger ») : les données
de test UTF-8 (`"café"`, `"ÉÀÙÇ"` dans `tests/regressions.ol` ; `"café"` et `"straße"` dans le
tutoriel), les plages Latin-1 de `string_module.cpp` (`à..þ`), le jeu de caractères de
`tools/gen_ui_font.cpp`, et le code généré ou vendorisé (`font_sans.h`, `font_mono.h`,
`docs/vendor/`, `docs/wasm/`, `libs/robin_hood.h`).

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
│   ├── shaders/       lit.vert / lit.frag — le GLSL de la 3D, EMBARQUÉ (cf. « Shaders »)
│   ├── modules/       modules natifs : core, math, string, color, date, window, mouse, keyboard,
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
│                      gen_rubik_glb.py (engendre docs/samples/rubik.glb — cube 3×3 texturé par un
│                      ATLAS ; l'image PNG est écrite par le script, cf. plus bas),
│                      gen_teapot_glb.py (engendre docs/samples/teapot.glb — la théière d'Utah,
│                      pavée depuis ses 32 patchs de Bézier ; le JEU DE DONNÉES est dans le script,
│                      donc aucun réseau, cf. plus bas),
│                      gen_terrain_glb.py (engendre docs/samples/terrain.glb — lancé à la MAIN,
│                      modèle À NOUS ; le seul à porter une couleur par sommet),
│                      convert_suzanne_obj.py (convertit le Suzanne de Khronos en
│                      docs/samples/suzanne.obj — lancé à la MAIN, réclame le réseau ; le script
│                      EST la trace de provenance d'un modèle emprunté, cf. plus bas),
│                      convert_dragon_glb.py (idem pour docs/samples/dragon.glb — dragon de
│                      Stanford, licence NON commerciale, cf. plus bas),
│                      convert_helmet_glb.py (idem pour docs/samples/helmet.glb — Damaged Helmet,
│                      crédit obligatoire et NON commercial, cf. plus bas),
│                      gltf_util.py (plomberie glTF partagée par les trois convertisseurs),
│                      ollin-vscode/ (extension VS Code, colorisation)
├── bench/             benchmarks (.ol / .lua / .py) + icount.sh (compte d'instructions)
└── docs/              tutoriel, playground, samples, wasm
                       docs/samples/ : un exemple d'UN fichier est posé à plat ; un exemple de
                       PLUSIEURS fichiers a son propre dossier (invaders/, voxel_world/, model_3d/,
                       primitives_3d/, transforms_3d/), avec SES données (les six modèles 3D sont
                       dans model_3d/), et une bibliothèque partagée par plusieurs d'entre eux vit
                       dans docs/samples/lib/ (trackball.ol, starfield.ol).
```

## Web app monopage (docs/)

Le site (`docs/`) est une **SPA** : une seule page hôte, plusieurs vues montées à la demande.

- `docs/index.html` — **shell** minimal : `#view` (point de montage) + `<canvas id="canvas">` partagé (rangé dans `#canvas-home` hors exécution) ; charge `app.js`.
- **Installation en application** (`docs/manifest.webmanifest`, déclaré par le shell) : sans manifeste
  annonçant `display: "standalone"`, le « Ajouter au Dock » de Safari sous macOS garde ses commandes
  de navigation dans la fenêtre, et cette bande recouvre notre propre barre d'outils — les boutons
  s'affichent mais les clics partent au navigateur, pas à la page (signalé par l'utilisateur). Les
  icônes PNG (`icon-192`, `icon-512`, `apple-touch-icon`) sont **engendrées depuis `logo.svg`** :
  sans elles, Safari prend une capture de la page comme icône. ⚠ Safari lit le manifeste **à
  l'installation** : une application déjà posée sur le Dock doit être retirée puis rajoutée.
  ⚠ **Une fenêtre d'application macOS est disposée de DEUX façons par Safari**, et c'est ce qui a
  coûté cinq corrections : au lancement la page remplit la fenêtre et la barre de titre est dessinée
  PAR-DESSUS (donc par-dessus notre barre), tandis qu'après un aller-retour en plein écran Safari
  pose la page SOUS la barre de titre (réserver de la place y donnait un espace mort). Mesuré sur le
  Mac de l'utilisateur via la section « This window » de `#/perf` : fenêtre `1536 × 930` dans les
  deux cas, page `1536 × 930` au lancement contre `1536 × 898` au retour. Le critère est donc
  `outerHeight − innerHeight` : nul, la barre est au-dessus de la page ; 32, elle est déjà réservée.
  Cette différence est un OUI/NON et **jamais** une hauteur — la lire comme une hauteur rendait un
  écart double au retour du plein écran, les valeurs lues pendant l'animation décrivant une autre
  fenêtre. `app.js` la mesure (`--mac-titlebar-measured`, relu 600 ms après le dernier `resize`),
  `app-bar.css` ne l'applique qu'en `display-mode: standalone`, et `--inset-top` (unique pour les
  quatre vues, appliqué par `.app-bar`) l'additionne à l'encoche iOS.
  Pistes fausses, à ne pas refaire : réserver la place selon l'ÉTAT (mode d'affichage, plein écran
  deviné par des seuils) — chaque version corrigeait un cas en cassant l'autre, parce que l'état ne
  dit rien de la disposition choisie par Safari ; et ne rien réserver du tout, ce qui laissait les
  barres se superposer au lancement. Leçon de méthode : sur une plateforme hors d'atteinte, faire
  AFFICHER les chiffres par l'application (d'où le relevé de `#/perf`) au lieu de raisonner sur des
  chiffres supposés.
  Le `viewport` n'a **pas** `viewport-fit=cover` : les `env(safe-area-inset-*)` des vues valent donc
  zéro, ce qui laisse iOS poser la page dans la zone sûre. Le changer déplacerait la mise en page
  d'iOS et ne se fera pas sans un appareil pour le vérifier.
- `docs/app.js` — **routeur** par hash. `#/<vue>[/<ancre>]` change de vue ; `#<ancre>` (sans `/`) = ancre interne de la vue courante (défilement, pas de re-montage). `ctx.anchor` = sous-chemin après la vue (ancre du tutoriel, ou paramètre de vue). Charge le runtime **WASM une seule fois** (`getOllin`, instance partagée) et déplace le canvas partagé dans la vue active.
- **Catalogue des exemples, classé par groupes** : `docs/samples/index.json` porte un champ
  `group` par entrée, et **l'ordre des groupes est celui de leur première apparition** — pas de
  seconde liste à tenir en accord. Le menu Projet ouvre le groupe en **sous-menu volant** (à côté
  de la ligne, comme un menu desktop) ; il **retombe** sur le remplacement du panneau, avec flèche
  de retour, quand la fenêtre est trop étroite pour un second panneau. `fillExampleGroup` construit
  la liste pour les deux chemins.
  ⚠ Le panneau volant est un **frère** de `#project-menu`, en `position: fixed` : `#project-menu`
  porte `overflow-y: auto`, et une boîte dont un axe n'est pas `visible` rogne aussi l'autre, si
  bien qu'un enfant serait coupé au bord du menu. Étant `fixed`, il ne suit pas le défilement du
  menu → replacé (ou fermé) sur l'événement `scroll` du parent. Il n'est essayé qu'à DROITE :
  le menu pendant d'un bouton à l'extrémité gauche de la barre, si la droite manque de place la
  gauche en manque davantage — un renversement serait une branche jamais exécutée (vérifié).
  `tests/check_samples.sh` garde le catalogue : fichier listé existant, `.ol` du dossier tous
  listés hors les trois bibliothèques d'import, groupes contigus.
- **Exemples en lecture directe** : `#/playground/sample/<fichier>` (et `#/run/sample/<fichier>`) ouvre un exemple `docs/samples/<fichier>` **depuis le dépôt, sans copie ni persistance** (re-`fetch` frais à chaque chargement → un refresh reprend la version du dépôt). Édition libre non enregistrée ; bouton « Créer un projet » pour forker dans IndexedDB. Les projets utilisateur (IndexedDB) restent le mode par défaut.
- `docs/views/<vue>.html` + `docs/views/<vue>.js` — chaque vue = un fragment (CSS + markup, `<style>` actif seulement monté) + un module `export function init(ctx) → cleanup()`. `ctx = { root, getOllin, hardReload, navigate }`. Vues : `tutorial`, `playground`, `run`, `perf`.
- **Aperçu d'une ressource (vue `playground`)** : cliquer une ressource du rail l'affiche **à la place de l'éditeur** — `#res-view`, frère de `#editor-wrap` dans `#editor-main`, l'un masquant l'autre. Une image est rendue sur un damier (sinon un fond transparent se confondrait avec le panneau) avec ses dimensions et son poids ; tout autre format n'a qu'une fiche d'information. `currentRes` (nom, ou `null` = on édite) sert aussi aux deux rails pour la ligne active, si bien qu'un seul élément paraît sélectionné. Ouvrir un script, re-cliquer la ressource affichée ou la supprimer ramène à l'éditeur.
- **Capture d'écran (mode plein écran, vue `run`)** : le bouton « Capture » range un PNG dans les **ressources du projet actif** (`project.resources[nom] = {b64, ext}`), puis le déclare au moteur (`preloadImage`) → utilisable aussitôt par `image.load(nom)`. L'image vient du MOTEUR, en deux temps (`requestCapture` / `takeCapture`, bindings de `wasm_main.cpp`) : elle ne peut être lue qu'en **fin de frame**, et `canvas.toDataURL` rendrait une image vide (le contexte WebGL n'a pas `preserveDrawingBuffer`). En pause, la vue reprend la boucle le temps d'une frame. Un exemple lu depuis le dépôt n'a pas de projet où ranger l'image → message explicite.
- `docs/playground.html` / `docs/run.html` — **redirections** vers `index.html#/playground` / `#/run` (anciens liens). La source unique est `docs/views/`.
- **Toute écriture GitHub passe par `commitOnBranch` (`pg-github.js`), qui se REJOUE sur la
  nouvelle tête.** Lire la référence puis la faire avancer n'est pas atomique : si la branche a
  bougé entre les deux, GitHub répond `422 — Update is not a fast forward` (constaté par
  l'utilisateur). La séquence entière est refaite, lecture de la référence comprise, jusqu'à trois
  fois — le rappel qui construit l'arbre est rappelé à chaque tentative, sans quoi un envoi rejoué
  ressusciterait les fichiers qu'un autre commit venait de retirer. Les blobs, eux, sont créés
  UNE fois en dehors de la boucle : ils ne dépendent pas de la tête (vérifié : deux blobs envoyés
  malgré trois tentatives). Rejouer est sûr des deux côtés — un envoi écrit l'état local, que le
  modèle de synchronisation tient pour la vérité, et une suppression met des chemins à `null`,
  ce qui est idempotent.
- **Supprimer un projet synchronisé supprime AUSSI son dossier GitHub**, la case étant cochée par
  défaut (`renderMenuDelete`, `GH.deleteRemoteProject`). Laisser la copie distante n'était pas une
  décision mais un oubli, et il avait deux effets : le projet réapparaissait sous « Remote » dans
  le menu d'ouverture, et son nom restait pris, la recherche de nom libre lisant aussi la liste
  distante. La suppression distante passe AVANT la locale : si elle échoue, le projet reste entier
  des deux côtés plutôt que de perdre sa copie locale en laissant un dossier orphelin. Décocher
  garde la copie GitHub (libérer la place locale sans perdre la sauvegarde).
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
| `tests/check_html.sh` | Claude | **garde-fou de balisage** : les fragments de `docs/views/` et le shell doivent être correctement imbriqués — une balise non fermée ne cassait aucun test, le navigateur réparant l'arbre en silence (constaté : les deux `</div>` du rail écrasés par une passe d'édition, la liste des fichiers et tout « Resources » se retrouvant DANS l'en-tête « Files ») |
| `tests/check_samples.sh` | Claude | **garde-fou du catalogue** : `docs/samples/index.json` est le seul lien entre le menu du playground et les fichiers — un renommage y laissait une entrée morte que RIEN ne détectait, la panne n'apparaissant qu'à l'ouverture du menu dans le navigateur |
| `docs/grammar.ebnf` | Claude | **grammaire formelle = référence de la syntaxe du langage** (dérivée de `syntax.ol`) |
| `docs/views/tutorial.html` | Claude | tutoriel HTML (vue de la web app monopage) |
| `docs/views/perf.html` + `perf.js` | Claude | vue `#/perf` : rapport de performances du moteur — le TRAVAIL (`docs/data/icount-history.json`, série historique) et le TEMPS (`docs/data/bench-snapshot.json`, relevé unique), plus la section « This window » : tout ce que la page sait de sa fenêtre, seule preuve exploitable quand la mise en page est fausse sur une machine hors d'atteinte |
| `tools/ollin-vscode/` | Claude | extension VS Code (colorisation) |

**Règle** : toute évolution de la syntaxe doit mettre à jour simultanément `grammar.ebnf` (référence), `tests/syntax.ol` (qui doit EXERCER la forme nouvelle, pas seulement la mentionner), `docs/views/tutorial.html` et `tools/ollin-vscode/`. **Répartition des tests, sans recouvrement** : la FORME dans `tests/syntax.ol` (une construction du langage y figure toujours — une forme couverte seulement ailleurs est un manque), le COMPORTEMENT dans `tests/regressions.ol` (sémantique fine, cas limites, ce qui a déjà été cassé), l'ÉCHEC dans `tests/test_errors.sh` (ce qui doit être refusé, et avec quel message) — un échec RATTRAPÉ par `try`/`catch` reste du comportement, `test_errors.sh` ne sait vérifier qu'un message rendu sur la sortie d'erreur. Un test de sémantique qui n'exhibe aucune forme nouvelle n'a rien à faire dans `syntax.ol`. **La couverture est vérifiée par `tests/check_grammar_coverage.sh`** (dans `run.sh`) : chaque section de `syntax.ol` porte une étiquette `## [grammar: forStmt, rangeLit]` citant les règles qu'elle exerce, et le script échoue si une règle de `grammar.ebnf` n'est citée nulle part — ou si une étiquette cite un nom qui n'existe pas. Il compare des NOMS, il ne lit pas le code : l'étiquette engage celui qui la pose. Ajouter une règle à la grammaire oblige donc à écrire son test. CLAUDE.md n'est mis à jour que si l'implémentation (opcodes, stratégie de compilation, structures) change.

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
  `T_MODULE`), +4,6 % (globales `W`/`H`), +1,8 % (expansion de `...`, `CX`/`CY`), +0,6 %
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

> API : voir le tutoriel (`docs/views/tutorial.html`, section « Module ui »).

Widgets dessinés par le moteur, en pile dans le coin haut droit. Le moteur appelle le
module en trois endroits de sa boucle de rendu (`graphics_module.cpp`, `run_user_callbacks`) :

- **`ui_poll()` AVANT `mouse_poll(...)`** : il renvoie true s'il a consommé le clic, et
  `mouse_poll(click_taken)` neutralise alors `pressed`/`released`/`doubleClicked`. C'est
  LA raison d'être d'un module natif plutôt qu'une classe Ollin : une classe ne peut pas
  s'interposer, elle devrait voler les callbacks du script (cf. l'avertissement en tête
  de `joystick.ol` et de `trackball.ol`, qui réclament trois relais chacun).
- **`ui_draw()` APRÈS la COMPOSITION**, dans `render_frame` et non plus dans
  `run_user_callbacks` : l'interface est **indépendante du viewport** (décision de
  l'utilisateur), donc elle se dessine dans les coordonnées de la ZONE, par-dessus le champ
  déjà composé et jusque sur les bandes du letterbox — un widget garde ainsi sa taille quelle
  que soit la résolution virtuelle choisie par le jeu. Elle reste **avant**
  `flush_pending_screenshot`, ce qui la fait capturer par `graphics.screenshot`, et toujours
  après `end3d_internal()`, donc par-dessus la 3D. Le chemin de repli (sans render texture)
  l'appelle juste après `run_user_callbacks`, faute de composition à attendre.
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
- **Ordre de lecture d'une ligne : le libellé à GAUCHE, le contrôle à DROITE.** La valeur d'un
  slider, celle d'une liste et le chevron d'un sous-menu étaient déjà cadrés à droite ; la case
  d'une checkbox l'est aussi. Toutes les cases ayant la même taille, leurs bords gauches
  s'alignent d'eux-mêmes — aucune colonne à calculer.
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

> API : voir le tutoriel (`docs/views/tutorial.html`, section « Module touch »).

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

> API : voir le tutoriel (`docs/views/tutorial.html`, section « Modules audio et sound »).

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

> API : voir le tutoriel (`docs/views/tutorial.html`, section « Module tween »).

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
  `graphics.font([nom])` le pilote et renvoie le nom courant ; `graphics.textSize(valeur)`
  mesure avec la police ET la taille courantes (deux valeurs, via `ctx.set_result`).
- **Un argument texte se convertit ou se refuse, jamais ne s'ignore.** La conversion est
  réservée à ce que le moteur DESSINE — `graphics.text` et `graphics.textSize`, par
  `drawn_text` (graphics_module.cpp), donc `value_to_string` et la méta-méthode `__str` comme
  `print`. **Partout ailleurs la chaîne est obligatoire** : un titre de fenêtre ou un message
  d'`assert` est écrit par l'auteur, un nombre y est une faute et non un raccourci (une valeur
  s'y insère par interpolation, `"level {n}"`), et un identifiant — police, mode de fusion,
  sorte de lumière, nom de touche, clé de `data` — n'a aucun sens en nombre. Le troisième
  comportement, remplacer en SILENCE par un défaut, était le pire des trois et a été éliminé :
  `graphics.text(score, x, y)` ne dessinait rien, un titre non-chaîne devenait « Ollin »,
  `blendMode(nil)` retombait sur `alpha`, `light(1, …)` allumait une directionnelle, et
  `assert(false, 42)` perdait son message.
- **Le type du message d'`assert` est vérifié même quand l'assertion TIENT** : le contrôler
  seulement à l'échec cacherait la faute jusqu'au jour où l'assertion casse. Figé dans
  `test_errors.sh` (les deux refus) et dans `regressions.ol` (un message chaîne remonte
  intact, l'absence de message donne « assertion failed »).
- **`graphics.text` accepte TOUTE valeur**, convertie par `value_to_string` — donc comme
  `print`, méta-méthode `__str` comprise. Auparavant un non-string devenait la chaîne vide :
  `graphics.text(score, x, y)` ne dessinait rien, sans erreur ni diagnostic. `textSize` fait la
  même conversion, sinon on pourrait écrire un nombre sans jamais pouvoir le centrer (vérifié :
  mêmes largeur et hauteur pour `42` et `"42"`, pour une instance et son `__str`).
  ⚠ **La géométrie est lue AVANT la conversion** : `__str` est du code Ollin, son appel peut
  redimensionner le fichier de registres, et `ctx.args` serait alors pendant. La conversion vient
  aussi APRÈS le test de police, pour qu'un `__str` ne s'exécute pas quand il n'y a rien à dessiner.
  Non couvert par `tests/run.sh` (graphics y est nil) : mesuré sous Xvfb avec `build-gfx/ollin`.
- `tests/check_naming.sh` **exclut** `font_sans.h`/`font_mono.h` : les identifiants d'un
  fichier généré sont ceux de l'outil, et une correction serait effacée à la génération
  suivante.

## Orientation verticale d'une image (`image_module.cpp`)

Une texture n'est retournée que si son contenu a été écrit **par RENDU** dans le framebuffer
(OpenGL range alors ses lignes de bas en haut). `TexHandle::gpu_flipped` porte ce fait : vrai
depuis `image.beginDraw`, faux dès qu'un `UpdateTexture` recopie l'ombre CPU. Le drapeau ne se
remet à zéro qu'en **un seul point**, `upload_cpu` — l'unique endroit où l'ombre CPU atteint la
texture —, si bien qu'un futur chemin d'écriture qui passe par lui est correct sans qu'on y pense. C'est ce drapeau, et non `is_render`, que lisent `image.draw` et
`image_draw_sprite`. Auparavant TOUTE texture de rendu était retournée au dessin, si bien qu'un
motif rempli côté processeur s'affichait à l'envers — constaté sur les boucliers d'`invaders.ol`,
et vérifié dans les deux sens : une image peinte par rendu garde son sens, un aller-retour
`beginPixels`/`endPixels` après un rendu aussi (la relecture `LoadImageFromTexture` est retournée
quand `gpu_flipped`, pour que l'ombre CPU reste de haut en bas).

Le chemin 3D n'est pas concerné : `graphics.texture` passe par `image_gl_texid`, qui ne décide
d'aucun sens (l'atlas de tuiles est échantillonné sans retournement, cf. « Affichage 3D »).
⚠ **Trou connu, antérieur et non corrigé** : `image_gl_texid` rend l'identifiant GL nu, donc une
image peinte par `beginDraw` puis posée en texture 3D est renversée en silence. Le corriger demande
de faire traverser le sens à cette frontière (`image_gl_texid(id, bool*)`) et de le lire dans
`graphics3d.cpp` ; aucun exemple ne l'exerce, tous les atlas étant remplis côté processeur.

## Viewport (résolution virtuelle, `graphics.viewport`)

`graphics.viewport(w, h)` fait dessiner le script dans un champ de `w × h`, que le moteur met à
l'échelle et centre dans la zone, bandes noires à côté. Sans argument, le viewport est abandonné.

Il se glisse en **trois** points, et nulle part ailleurs :
1. le `rlOrtho` de `render_frame` prend les dimensions virtuelles au lieu des logiques — la render
   texture garde la résolution de l'appareil, si bien qu'un sprite agrandi reste net (texture en
   NEAREST) et que le texte reste lisse ;
2. la **composition** vise le rectangle du letterbox au lieu de l'écran entier, avec un
   `ClearBackground` pour peindre les bandes (sans lui, la frame précédente reste visible à côté) ;
3. `gfx_view_map` convertit les coordonnées d'entrée — `mouse_poll`, `mouse.position()` et
   `touch_begin_frame` — pour que le script reçoive des positions dans le repère où il dessine.
   ⚠ **Tout seuil exprimé en pixels d'ÉCRAN garde les coordonnées brutes** : le test de double-clic
   (`mouse_poll`) et la distance minimale du pincement (`Point::raw_x/raw_y`, lu par `pinch_poll`),
   sinon un champ virtuel étroit les divise par le facteur d'échelle — un pixel de garde-fou devenait
   un huitième de pixel réel.
   ⚠ `gfx_view_map` rend un **booléen** « un viewport est actif » : sans viewport les positions
   restent des ENTIERS, comme tous les scripts existants les reçoivent depuis toujours. Une
   conversion neutre doit l'être jusqu'au type — un `Value(double)` inconditionnel changeait
   l'affichage, les clés de map et les égalités entières de tout le dépôt.

`W`/`H`/`CX`/`CY` valent la taille **virtuelle** (décision de l'utilisateur) : le script n'a qu'un
seul repère à connaître. `window.width`/`height` continuent de rapporter la zone RÉELLE.
`graphics.canvas` abandonne le viewport — il appartient au programme qui l'a demandé — et la
publication des quatre globales passe par un seul endroit, `publish_draw_size`.

**Ce qu'il ne fait pas** : l'interface `ui` est indépendante (cf. plus haut), et la 3D tire son
rapport d'aspect de la fenêtre et non du viewport — c'est une fonctionnalité 2D.

## Globales moteur (engine-injected globals)

Des globales sont injectées par le moteur, sans déclaration `global` dans le script :

| Nom | Type | Description |
|-----|------|-------------|
| `deltaTime` | FLOAT | Secondes écoulées depuis la frame précédente (`GetFrameTime()`) |
| `elapsedTime` | FLOAT | Secondes écoulées depuis le démarrage du programme (somme des deltaTime) |
| `W` | INTEGER | Largeur de la zone de rendu (défaut : `window.width` selon l'environnement) |
| `H` | INTEGER | Hauteur de la zone de rendu (défaut : `window.height`) |
| `CX` | FLOAT | Centre X de la zone de rendu (`W / 2`) |
| `CY` | FLOAT | Centre Y de la zone de rendu (`H / 2`) |

**Implémentation** :
- `declared_globals_` les contient (pré-ajoutés dans `Compiler::compile()`) → le compilateur accepte ces noms sans `global`.
- `VM::execute()` initialise `deltaTime`/`elapsedTime` à `0.0`, `W`/`H` (int) aux dimensions de `window` (lues via `makeBuiltinModule("window")`) et `CX`/`CY` (float) à `W/2`/`H/2` **avant le top-level** — ainsi `graphics.canvas(W, H)` fonctionne dès le script principal.
- `gfx_canvas()` (graphics_module.cpp) **repositionne** `W`/`H`/`CX`/`CY` sur les dimensions logiques réelles à chaque `graphics.canvas(w, h)` (via `setGlobal`) → les globales suivent la taille effective du canvas, même si elle diffère du défaut `window`.
- `VM::setGlobal(name, value)` — méthode publique qui trouve l'identifier par nom et met à jour `globals[i]`. Appelée par `callUpdateIfAny()` dans `graphics_module.cpp` avant chaque frame.
- `s_elapsed_time` (statique dans `graphics_module.cpp`) est remis à 0 à chaque `gfx_run()`.
- **Canvas implicite** : `VM::runEntryHooks()` — si un `draw()` existe et que `graphics` est un module (pas le stub), mais que `graphics.canvas()` n'a **pas** été appelé (drapeau `VM::gfxCanvasCreated()`, posé par `gfx_canvas` via `markGfxCanvas()`), le moteur appelle `graphics.canvas(W, H)` → une session graphique démarre sur la seule présence de `draw()`. **Fait APRÈS `setup()`** : `setup()` est un endroit courant pour appeler `canvas()` soi-même ; le créer avant provoquerait un **double `InitWindow`** (crash « memory access out of bounds » en WASM). Le drapeau vit sur le VM (neuf à chaque run playground) → détection fiable même avec le contexte WebGL réutilisé.

**Une frame que la boucle n'a PAS exécutée n'est pas du temps passé par le programme**, et cette
interruption est **DÉCLARÉE, jamais devinée** : `gfx_clock_break()` (graphics_internal.h) arme le
moteur, et la première frame de retour compte **zéro** au lieu de l'écart d'horloge. Qui arrête la
boucle le dit — le bouton Pause du playground et de la vue `run` (`mod.clockBreak()` avant
`resumeMainLoop`, capture comprise puisqu'elle relance la boucle le temps d'une frame), les
écouteurs DOM posés une fois par le moteur (`visibilitychange`, `focus`, `blur`, `pageshow`, qui
lèvent un drapeau relu par la frame), et sur desktop la reprise du focus ou la sortie de
minimisation. Mesuré au navigateur : sur 5 s de pause, le plus grand `deltaTime` du programme reste
celui d'avant la pause (0,098 s) — **aucun saut**, contre 5,126 s à l'origine.

⚠ **Plafonner l'écart a été essayé puis RETIRÉ** (`MAX_FRAME_DT = 0,25 s`) : le plafond créditait
encore sa propre valeur à chaque reprise — un quart de seconde d'animation venu de nulle part — et
il punissait une frame simplement lente. Un arrêt connu doit rendre zéro, pas « peu ».

**Ce qui reste NON couvert, faute de signal** : une interruption que personne n'annonce — mise en
veille de la machine, `SIGSTOP`, un débogueur, ou une plateforme dont le déplacement de fenêtre
bloque notre boucle (constaté par la mesure : un gel de 4 s par `SIGSTOP` sous Xvfb rend un
`deltaTime` de 4,009 s). Aucune API ne le rapporte, et un seuil qui le devinerait serait justement
la bidouille écartée ci-dessus.

**Règle d'animation** : utiliser `elapsedTime` (ou `deltaTime` accumulé manuellement) plutôt que `time()`. `time()` utilise `Date.now()` dans le navigateur (précision réduite) ; les globales moteur sont basées sur `GetFrameTime()` / `performance.now()`, plus précis et sans artefact.

## Shaders (src/shaders/)

Le GLSL vit dans **`src/shaders/lit.vert` et `lit.frag`**, pas dans du C++. Il est **embarqué** :
`CMakeLists.txt` lit ces fichiers à la CONFIGURATION (`file(READ)` + `configure_file` sur
`src/modules/shader_sources.h.in`) et les colle dans un header généré,
`${CMAKE_BINARY_DIR}/generated/shader_sources.h`, sous forme de chaîne brute. Rien n'est lu sur
le disque à l'exécution — même principe que les polices : le rendu est identique sur toutes les
cibles, WASM comprise, et aucune option de build ne peut le changer.

- **La ligne `#version` n'est PAS dans les `.glsl`** : elle dépend de la cible (`300 es` sous
  emscripten, `330` ailleurs) et `load_lit_shader` la préfixe. C'est le seul morceau de GLSL
  resté en C++.
- **Éditer un `.glsl` suffit** : `CMAKE_CONFIGURE_DEPENDS` relance la configuration
  automatiquement au rebuild, sans appeler `cmake` à la main (vérifié en changeant l'ambiante
  du fragment et en constatant le changement à l'écran après un simple `cmake --build`).
- Les identifiants GLSL (`fragTexCoord`, `instanceTransform`…) sont en camelCase et échappent aux
  conventions C++ : `check_naming.sh` ne parcourt que `src/**/*.cpp` et `src/**/*.h`, donc ni les
  `.glsl` ni le `.h.in`. Le header généré vit dans `build*/`, ignoré par git.
- **Un seul couple de shaders** pour toute la 3D. Il porte cinq sujets — éclairage Blinn-Phong,
  atlas de tuiles, eau animée, hauteurs de coin, test alpha du feuillage. Chaque instance
  transporte donc 7 flottants (tuile + coins) même quand elle n'en fait rien, et le fragment teste
  `fragTile.x >= 0` à chaque pixel. C'est une **dette assumée** : séparer en variantes ferait
  entrer le programme dans la clé de regroupement des instances (aujourd'hui `(maillage, texture)`),
  donc un tri et des changements d'état en cours de frame. Seuil de bascule : une **sixième**
  fonctionnalité, ou un attribut d'instance supplémentaire.
  La couleur par sommet ne compte NI pour l'une NI pour l'autre, et c'est vérifiable : elle
  n'ajoute aucune branche (une multiplication de plus dans `fragColor`) et rien à l'instance —
  l'attribut est celui du MAILLAGE, déjà présent dans son VAO. Le seuil est inchangé.

## Modèles 3D des exemples (docs/samples)

Six fichiers, chacun pour une raison distincte : `rubik.glb` (glTF portant une TEXTURE, en ATLAS),
`suzanne.obj` (géométrie seule, la teinte vient du `fill` — et 3 936 triangles de vraie géométrie
sculptée), `dragon.glb` (la masse : 91 216 triangles) et `helmet.glb` (une vraie texture peinte SUR
de la géométrie sculptée, ce que `rubik.glb` ne fait que prouver possible), `terrain.glb`
(une couleur PAR SOMMET, cf. plus bas) et `teapot.glb` (la théière d'Utah, une SURFACE
PARAMÉTRIQUE que le script pavage lui-même, cf. plus bas).

**Plus aucun modèle ne porte une couleur de matériau PAR MAILLAGE** : `armillary.glb` était le
seul, et il a été retiré à la demande de l'utilisateur. Le chemin existe toujours dans
`drawModel` (la couleur diffuse est lue par maillage et multipliée par le `fill`), mais il n'est
plus exercé par aucun exemple — c'est un trou de couverture connu, pas un oubli.

**Les trois convertisseurs partagent `tools/gltf_util.py`** — lecture d'un conteneur `.glb`,
lecture d'un accesseur, rotation par quaternion, écriture d'un `.glb`. Chacun avait recopié les
quatre, ce qui est exactement la duplication que le module supprime ; le refactor a été vérifié
par l'octet (sortie identique avant/après).

**Couleur PAR SOMMET** : `terrain.glb` (engendré par `tools/gen_terrain_glb.py`, modèle à nous,
aucune licence tierce) porte un `COLOR_0` et se colore par l'altitude — un seul maillage, beaucoup
de couleurs, aucune image, un seul appel de dessin. Côté moteur, `lit.vert` déclare `in vec4
vertexColor` : raylib lie ce NOM à l'emplacement d'attribut 3 avant l'édition de liens
(`glBindAttribLocation`, `rlgl.h`), qui est justement celui du VBO de couleurs d'un maillage.
⚠ Un maillage SANS `COLOR_0` laisse cet emplacement sans tampon, et OpenGL sert alors la valeur
générique — `(0, 0, 0, 1)` par défaut, donc un modèle NOIR. `lit_begin_draw` pose donc la constante
blanche une fois par dessin (`rlSetVertexAttributeDefault`), un maillage qui a le tampon
l'emportant depuis son propre VAO ; c'est ce que fait raylib dans son `DrawMesh`. Vérifié : les
rendus de Suzanne et du casque sont identiques à l'octet avant et après le changement.

**Texture en ATLAS** : `rubik.glb` (engendré par `tools/gen_rubik_glb.py`, modèle à nous) remplace
un cube enveloppé dans un damier 4×4 répété, qui montrait la MÊME image sur les six faces — le
minimum qu'une texture puisse prouver. Un cube 3×3 résolu exige un atlas : une seule image, six
cellules, chaque face lisant la SIENNE par ses UV.
Les **26 pièces sont de la vraie géométrie** séparée par un jeu (`GAP3D`), et non une grille peinte
sur une seule boîte : les arêtes de chaque petit cube se voient alors, sur la silhouette comme dans
les creux, et la lumière les accroche. La pièce centrale est omise, elle ne peut pas être vue. Les
UV d'une face extérieure sont calculées **depuis la position** du sommet sur la face (`face_uv`),
donc le motif peint s'aligne sur la géométrie par construction, sans table à tenir en accord ; les
faces tournées vers l'intérieur prennent un texel du corps noir. 624 sommets, 312 triangles,
23,8 Ko.
Le **cube est MÉLANGÉ PAR DES ROTATIONS LÉGALES** (25 quarts de tour, graine fixe) : l'état est
donc réel et résoluble, et le fichier reproductible. **Aucune table d'adjacence n'a été écrite** —
un sticker est identifié par la POSITION de sa pièce et sa propre NORMALE, et un quart de tour fait
tourner les deux vecteurs, si bien que la géométrie tient la comptabilité. C'est l'idée des UV
ci-dessous, et c'est ce qui rend les tours contrôlables : `check_layout` vérifie que **quatre tours
identiques ramènent le cube à son état de départ**, que les 54 stickers sont bien là et qu'il en
reste neuf de chaque couleur. Vérifié aussi à zéro tour : chaque face ressort unie et de la bonne
couleur, ce qui valide le placement des stickers dans l'atlas. Un cube résolu n'aurait montré qu'une
couleur par face, soit ce que l'atlas est censé dépasser.
Le PNG (204×136) est dessiné pixel par pixel et encodé par le script, donc sans dépendance. Trois
points appris à la mesure : la grille doit remplir sa cellule EXACTEMENT (`3 × sticker + 4 ×
interstice == cellule`, sinon le pixel qui reste élargit la dernière bordure et les stickers ne sont
plus centrés — c'était le cas avec 3×9+4×1 = 31 pour une cellule de 32) ; les UV sont **rentrés d'un
demi-pixel** dans leur cellule (sans quoi le bord échantillonne la face voisine et une bande de la
mauvaise couleur court le long des arêtes) ; et l'orientation des quads est **vérifiée par le
calcul** (`check_layout`) — mes deux faces latérales étaient enroulées à l'envers, donc éliminées
par le back-face culling, et rien ne le signale : le cube sortait simplement ouvert sur deux côtés,
ce qu'un rendu seul a révélé.

**Surface PARAMÉTRIQUE** : `teapot.glb` n'est pas un maillage emprunté mais la théière de Martin
Newell (Utah, 1975) — **32 patchs de Bézier bicubiques sur 290 points de contrôle** — pavée par
`tools/gen_teapot_glb.py`, qui porte le jeu de données en littéral. Trois conséquences : le modèle
se reconstruit à **n'importe quelle finesse** (constante `STEPS`), il ne dépend d'AUCUN hôte — tous
les sites qui publient les fichiers `.bpt` sont refusés par le proxy — et les normales viennent des
**dérivées** de la surface, pas d'une moyenne de faces. Les données de Newell circulent librement
et sans revendication de droits depuis cinquante ans ; celles-ci ont été **analysées, pas
retapées**, depuis la tabulation du README de `github.com/LUXOPHIA/UtahTeapot` (celle qui complète
les patchs symétriques omis par la liste de Steve Baker), et vérifiées à la lecture : 32 patchs,
290 points, indice maximal 289.
⚠ Plusieurs patchs **dégénèrent** (une rangée entière repliée sur un seul point : pointe du
couvercle, extrémités du bec) — une tangente y est nulle, donc le produit vectoriel aussi.
`patch_normal` échantillonne alors légèrement en retrait au lieu de rendre un vecteur nul.

**Un maillage raylib ne peut pas dépasser 65 535 sommets** : `Mesh` range ses indices en
*unsigned short*, et le chargeur CONVERTIT un tampon d'indices 32 bits en 16 bits avec un simple
avertissement. Le dragon (76 809 sommets d'un seul tenant) sortait donc en gerbe de triangles
pointant n'importe où — constaté à l'écran, pas déduit. `tools/convert_dragon_glb.py` le découpe
en primitives de 65 535 sommets au plus (deux ici, donc deux maillages et un appel de dessin de
plus), ce qui est la seule correction possible côté données. Toute géométrie importée plus grosse
que cela rencontrera la même limite.

**Un modèle emprunté ne s'ajoute qu'avec sa provenance vérifiée et un script qui la rejoue.**
`suzanne.obj` vient de `KhronosGroup/glTF-Sample-Assets`, © 2017 UX3D, par Norbert Nopper, sous
**CC0 1.0 Universal** — domaine public, donc aucune obligation d'attribution, et le crédit est
gardé quand même dans l'en-tête du `.obj`. La licence a été LUE avant de prendre le fichier.
`tools/convert_suzanne_obj.py` retélécharge la source et refait la conversion glTF → OBJ : c'est
lui qui rend la provenance contrôlable au lieu d'un binaire mystérieux. Les coordonnées de texture
sont écartées (rien n'échantillonne de texture ici) et les nombres sont à quatre décimales, ce qui
suffit à un modèle d'affichage.

`dragon.glb` est le dragon scanné par le **Stanford Computer Graphics Laboratory**, repris de la
décimation de `KhronosGroup/glTF-Sample-Assets` (`DragonAttenuation`) par
`tools/convert_dragon_glb.py`. Sa licence **n'est pas CC0** : elle exige le crédit, autorise la
redistribution gratuite mais **interdit l'usage commercial sans autorisation** — restriction
portée par ce seul fichier, à connaître avant d'en faire quoi que ce soit d'autre. Le crédit vit
dans `asset.copyright` du glTF. Seul le maillage du dragon est repris (la scène d'origine a un
fond de tissu et des extensions de verre que notre shader ignore), la rotation du nœud est cuite
dans les sommets ET les normales (quart de tour autour de X ; l'échelle étant uniforme, elle ne
touche pas les normales), et aucun matériau n'est écrit — le `fill` décide de la couleur.

`helmet.glb` est le **Damaged Helmet**, le modèle que tous les moteurs de rendu PBR montrent
depuis 2016, repris de `KhronosGroup/glTF-Sample-Assets` par `tools/convert_helmet_glb.py`. Sa
licence est **double** : © 2018 ctxwing pour la reconstruction et la conversion glTF (CC-BY 4.0),
© 2016 theblueturtle_ pour la version antérieure du modèle (**CC-BY-NC** 4.0) — crédit obligatoire
et pas d'usage commercial, comme le dragon. Les deux crédits vivent dans `asset.copyright`. Seules
la géométrie et la texture de couleur de base sont reprises : la source porte aussi des cartes
métallique-rugosité, émissive, d'occlusion et de normales que notre shader n'échantillonne jamais,
soit 2,7 Mo que le moteur ne peut pas lire (1,5 Mo livré contre 3,8 Mo à la source).

## Affichage 3D + éclairage (graphics_module.cpp)

La 3D s'appuie sur raylib (`Camera3D`, `BeginMode3D`/`EndMode3D`, `GenMesh*`) mais les **solides pleins** passent par un **batcher retained à instancing** avec un shader Blinn-Phong custom. Fonctionne desktop (GL 3.3) **et** WebGL2/GLES3 (vérifié).

- **Intégration frame** : `graphics.begin3d(cam)` → `BeginMode3D` (perspective + depth test) et réinitialise les buckets ; `graphics.end3d()` flushe les buckets puis `EndMode3D` (restaure l'ortho 2D → HUD 2D possible ensuite). Bloc ouvert **dans** `draw()`, donc dans la `RenderTexture` `s_target`.
- **Batcher instancié** : `cube/sphere/cylinder/plane` en `fill` n'affichent rien — ils **empilent** une instance `{transfo = local·pileMatrices, tint = couleur fill}` dans un bucket `(shape, texture)` (`s_buckets`), où `local = scale·translate` (placement) et `pileMatrices = rlGetMatrixTransform()` capturée à l'appel. `end3d`/`flush3dBuckets` résout chaque bucket en **UN** `DrawMeshInstanced` custom (réplique de raylib + **2ᵉ VBO d'instance couleur** → couleur PAR INSTANCE) avec des VBO d'instance **persistants** (create/grow + `glBufferSubData`, pas de churn). Meshes unitaires en cache (`GenMeshCube/Sphere/Cylinder/Plane`) ; draw indexé ou non selon `mesh.indices`. Le **fil de fer** (`stroke`), `grid`, `line3d`, `point3d` restent en **immédiat non éclairé** (dessinés pendant la collecte ; `flush3dBuckets` fait `rlDrawRenderBatchActive` avant les draws instanciés).
- **Transformations 3D** : `translate(x,y[,z])`, `rotate(deg[,ax,ay,az])`, `rotateX/Y/Z(deg)`, `scale(s|sx,sy|sx,sy,sz)` pilotent la pile rlgl. `begin3d` fait un `rlPushMatrix` (refermé par `end3d`) → tout le bloc est en mode « transform » : translate/rotate/scale écrivent dans `RLGL.State.transform` (espace monde, lu par `rlGetMatrixTransform()`) **qu'ils soient encadrés par `push`/`pop` ou « nus »** (cumulatifs). Chaque instance fige cette transfo (`pushInstance`), et les primitives immédiates l'appliquent (`transformRequired`) → même sémantique pour tous. Le MVP du flush utilise `s_view3d` (vue figée au `begin3d`), la modelview restant = vue.
- **Shader** (`loadLitShader`, embarqué en littéral, `#version 330` desktop / `300 es` WASM via `#ifdef __EMSCRIPTEN__`) : `instanceTransform` (auto) + `instanceColor` (attribut custom via `GetShaderLocationAttrib`) + `texture0`. `final = texture(uv) × tint`, puis Blinn-Phong (ambient + 1 lumière). **Opt-in** : sans lumière (`s_lighting_used=false`), ambient forcé à blanc + lumière off ⇒ rendu plat (aucune régression).
- **Une direction nulle est REFUSÉE** pour une lumière directionnelle (`apply_light_from_instance`,
  donc à la création comme au `setDir`) : le shader calculerait `normalize(vec3(0))`, indéfini —
  mesuré comme « la lumière ne contribue rien » sur llvmpipe, mais rien ne le garantit ailleurs. Une
  lumière ponctuelle n'a pas ce cas, sa position étant un lieu et non une direction. Non figeable
  dans `test_errors.sh` (`graphics` y est nil) : vérifié sous Xvfb.
- **Éclairage** (phase 1 : ambient + 1 lumière) : `graphics.ambient(v|couleur)` ; `graphics.light("dir"|"point", x,y,z [,couleur])` renvoie un objet **classe `Light`** (patron `makeClass`) — méthodes `set_dir`/`set_pos`/`set_color`/`enable` qui mutent l'état global via `applyLightFromInstance`. Réinitialisé à chaque `gfx_run` (`reset3dLightingState`, statiques persistants en WASM).
- **Textures** : `graphics.texture(img)` lit l'id GL via `image_gl_texid(handle.id)` (accessor ajouté à image_module) ; `noTexture()` → texture blanche 1×1 (`whiteTexId`). `s_cur_tex3d` se comporte comme `fill`/`stroke` : remis à 0 dans `resetStyles` chaque frame.
- **Atlas de tuiles (terrain voxel)** : `graphics.tileset(img, cols, rows)` déclare un atlas (grille de tuiles, filtrage NEAREST) ; `graphics.tiles(top, side, bottom)` / `graphics.tile(t)` fixent les tuiles du prochain cube (état, comme `fill` ; -1 = aucune). Un **3ᵉ attribut d'instance** `instanceTile` (vec3, VBO `vboT` pour les chunks / `s_inst_vbo_tile` pour l'immédiat) porte le triplet ; le shader **choisit la tuile selon la normale** (dessus/côté/dessous) et échantillonne l'atlas (`(cell + fract(uv)) / atlasGrid`, inset anti-bleeding). `tile.x < 0` → chemin classique (texture0 @ fragTexCoord, modèles/immédiat). **1 seul draw call par chunk conservé** — l'atlas est lié par `drawChunk` (à la place du blanc). L'atlas est généré en Ollin via le module `image` (`create`/`set_pixel`/`end_pixels` — render texture, échantillonnée SANS flip V car mise à jour par `UpdateTexture`, pas par rendu).
- **Test alpha sur le chemin d'atlas** (`if (texel.a < 0.5) discard;`) : un trou de la TUILE perce le cube, ce qui permet un feuillage ajouré sans retirer un seul cube (`voxel_world.ol`, paramètre `trous` de `putTile`). Franc et non fondu, donc **indépendant de l'ordre de dessin** : les cubes restent dans le groupe opaque, rien à trier. Limité au chemin d'atlas (`fragTile.x >= 0`) — une texture semi-transparente posée sur un modèle garde son fondu, et l'eau n'est pas concernée (sa transparence vient de la couleur d'instance, pas de la texture).
- ⚠ **Le bloc `instanceCorner` du vertex shader est gardé par « cette instance PORTE des hauteurs
  de coin »** (`any(notEqual(instanceCorner, vec4(0.0)))`), et non par le seul déplacement nul.
  Sans cette garde, le recalcul de normale s'appliquait à TOUT maillage instancié : sur une sphère,
  chaque sommet de la calotte haute (`vn.y > 0.5`) voyait sa normale remplacée par la verticale, si
  bien que la calotte était éclairée comme une surface plane, avec une couture en escalier là où
  `vn.y` franchit 0,5 le long des anneaux du maillage. Signalé par l'utilisateur sur « Primitives 3D »,
  et visible aussi sur le cône et le dessus du cylindre. Le déplacement, lui, était bien neutre à
  zéro — c'est la normale qui ne l'était pas.
- **Dessus déformé (`graphics.corners(a,b,c,d)`)** : un **4ᵉ attribut d'instance** `instanceCorner` (vec4, VBO `vbo_k` pour les chunks / `s_inst_vbo_corner` pour l'immédiat) porte les hauteurs des 4 coins du dessus, en unités LOCALES. Le vertex shader déplace les sommets tels que `vertexPosition.y > 0` de l'interpolation bilinéaire des 4 coins — exacte aux coins (sommets du mesh unitaire à ±0,5) — et recalcule la normale de la seule face du dessus (`vertexNormal.y > 0.5`) depuis les pentes, sinon le relief resterait plat à l'œil. Les sommets hauts des faces latérales suivent la même valeur ⇒ pas de fissure. Défaut `(0,0,0,0)` ⇒ rendu inchangé pour tous les autres appels ; **aucun draw call de plus**. `s_cur_corner` est un état comme `s_cur_tile`, remis à zéro par `reset3d_frame_state`.
- **Tuile animée** : `graphics.tileAnim(t)` désigne une tuile dont l'UV défile (`uniform uTime` = `GetTime()`, `uniform animTile`) → eau qui ondule sans recuire les chunks.
- **Transparence (eau)** : à l'enregistrement, `endChunk` **scinde** les instances en 2 groupes selon l'alpha de la couleur d'instance (`col.a < 250` → groupe transparent) et renvoie `{id, idw, count, wcount}`. Chaque groupe garde son **propre mesh** (`s_rec_mesh` opaque = cube, `s_rec_mesh_w` transparent = **plane** pour l'eau) → l'eau est une **surface plane** au niveau de la mer (`graphics.plane`, une par colonne, jointives = surface continue), PAS une pile de cubes (sinon on verrait les faces internes). `drawChunk` dessine l'opaque (`id`) ; `graphics.drawChunkAlpha(handle)` dessine le transparent (`idw`) en `BLEND_ALPHA` (depth test+write gardés → occlusion propre). **Ordre obligatoire** côté script : TOUT l'opaque (boucle `drawChunk`) PUIS TOUTE l'eau (boucle `drawChunkAlpha`) dans le même `begin3d`. `freeChunk` libère les deux groupes. Les slots de `s_groups` libérés sont **recyclés** via `s_free_groups` (`placeGroup`) → `s_groups` reste borné en streaming infini ; un chunk sans eau ne crée **pas** de groupe transparent (`idw = 0`). `freeGroupById` ne rend un slot au pool que s'il était vivant (double-libération idempotente).
- **Caméra** : classe native `Camera` ; `graphics.camera(...)` renvoie une INSTANCE (`px,py,pz, tx,ty,tz, fovy`). Méthodes : `set_pos`, `look_at`, `move`, `orbit(angle rad, rayon [, hauteur])`. `cameraFromMap()` la relit (up +Y, perspective) ; `s_cam3d` fournit `viewPos` au shader.
- **Profondeur** : la RT raylib porte un depth buffer (desktop + GLES) ; `graphics.clear(couleur opaque)` efface couleur **+ depth** (`rlClearScreenBuffers`).
- **Garde-fou** : `s_in_3d` ; `runUserCallbacks` appelle `end3dInternal()` si `draw()` oublie `end3d` (flush + rééquilibre la pile). `end3d` idempotent.
- **Quaternions** (`graphics_quat.cpp`, math raymath pure, fichier séparé) : classe native `Quat` ; fabriques `graphics.quat()`/`quat_axis(ax,ay,az,deg)`/`quat_euler(pitch,yaw,roll)` (**degrés**) ; méthodes `mul`/`slerp`/`normalize`/`inverse`/`rotate_vec` (renvoient de NOUVELLES instances, valeurs immuables). `graphics.rotateq(q)` (dans graphics3d.cpp) applique `QuaternionToMatrix(q)` via `rlMultMatrixf` (gauche-multiplie comme `rlRotatef` → compose comme `rotate`). `quatFromInstance()`/`makeQuatInstance()` = pont graphics3d↔graphics_quat.
- **Perf/limites** : 1 draw call par `(shape, texture)` — le nombre de **couleurs** n'ajoute pas de draw call (couleur par instance). `cylinder` est **mono-rayon** (`x,y,z,r,h`) : contrainte du mesh unitaire figé. Models externes = extension additive (bucket déjà keyé `(mesh, texture)`).


## Résolution d'un `import` (le chemin résolu = IDENTITÉ du module)

Un chemin d'`import` est résolu **relativement au dossier du fichier importateur** (`base_dir_ +
path`, sauf chemin absolu), puis **normalisé** — `.` et `..` réduits (`path_normalise`, parser.cpp).
Le chemin résolu est l'**identité** du module : clé du registre de sources, clé de déduplication des
imports, et nom sous lequel un projet web forké range le fichier. Sans normalisation,
`model_3d/../lib/trackball.ol` et `lib/trackball.ol` étaient deux modules distincts — la bibliothèque
partagée par trois exemples aurait été analysée sous trois noms, et un projet forké aurait porté un
fichier dont le chemin remonte l'arborescence.

- **Le fichier d'entrée n'est PAS une exception** : `wasm_main.cpp` dérive `base_dir` du nom du
  fichier exécuté, comme `main.cpp` l'a toujours fait. Il passait `""` en dur, si bien qu'un exemple
  rangé dans un sous-dossier cherchait ses voisins à la racine — il tournait en natif et pas sur le
  web, et le 404 du préchargement était silencieux (constaté au navigateur).
- **La même règle vit en TROIS endroits** qui doivent rendre la même chaîne : `parser.cpp` (le
  moteur), et dans `docs/pg-run.js` le préchargement des imports d'un exemple
  (`preloadSampleImports`, qui part du dossier du fichier d'entrée) et le ramassage d'un fork
  (`collectSampleProject`). Les deux fonctions JS partagent `resolveImport`/`pathNormalise`.
- `tests/check_samples.sh` parcourt `docs/samples/**` et identifie un fichier par son **chemin
  relatif** ; il DÉDUIT les bibliothèques au lieu de les lister — un `.ol` importé par un autre en
  est une — et signale aussi un `import` visant un fichier disparu.
- **Ce qui doit rester dans le fichier d'ENTRÉE** : `setup`, `update`, `draw` et les rappels
  `mouse.*` / `touch.*` / `keyboard.*`. Un module ne peut pas les capter (cf. l'avertissement en
  tête de `joystick.ol` et de `trackball.ol`). En revanche un `global` déclaré dans un module est
  partagé, et une fonction de l'hôte peut lire un `const` du module (et l'inverse) : c'est ce qui
  permet de sortir les données et leurs constructeurs. ⚠ Un `const` de l'HÔTE, lui, est une locale
  du corps principal : un module ne le voit pas (`UFO_HUM` a dû suivre les sons dans `sounds.ol`).

## Ressources : `program_dir()` (une ressource se cherche À CÔTÉ du programme)

`graphics.model("rubik.glb")` et `image.load("logo.png")` désignent un fichier par un nom NU, sans
répéter le dossier du script. Ce nom est résolu **à côté du programme d'abord**, puis tel quel :
`program_dir()` (source_registry.h) porte le dossier du fichier d'entrée, posé une fois au
démarrage par `main.cpp` et `wasm_main.cpp` depuis `path_dir`, comme pour `base_dir`.

- **Ce que cela règle** : un exemple rangé dans son propre dossier y garde ses données, et il ne
  dépend plus du répertoire COURANT du processus — `LoadModel`/`LoadTexture` résolvent depuis le
  CWD, si bien que `model_3d` ne tournait en natif que lancé depuis `docs/samples/`.
- **Le nom écrit dans le code reste la clé** : le préchargeur web (`fetchAsset`, pg-run.js) cherche
  `<dossier de l'entrée>/<nom>` puis `<nom>`, mais déclare toujours l'octet sous le **nom nu**, que
  `graphics.model` et `image.load` interrogent. Un projet forké range donc ses ressources sous ce
  même nom.
- Les six générateurs et convertisseurs de `tools/` écrivent dans `docs/samples/model_3d/`.

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

## Sortir d'une construction : `break`, `continue`, `return`

Un saut qui QUITTE une construction doit la démonter, et le compilateur porte cette
responsabilité — pas la VM. Chaque niveau de `break_patches`/`continue_patches` retient donc
**où** il a été ouvert : la fonction (`func_depth`), la profondeur de `try` (`try_depth`) et
s'il s'agit d'un `switch`.

- **`break` dans un `switch` est REFUSÉ.** Un bras ne chute pas sur le suivant, donc il n'a rien
  à quitter ; et écrit dans une boucle il se lisait comme « sortir de la boucle » alors qu'il
  était capté par le `switch`, la boucle continuant. Le refuser est la seule lecture qui ne
  trompe pas. `continue`, lui, traverse et atteint la boucle — asymétrie voulue, testée.
- **`break`/`continue` dans une lambda déclarée dans une boucle sont REFUSÉS** : le saut visait
  une adresse du code de la fonction ENGLOBANTE, et le corps de la boucle était purement sauté,
  sans erreur.
- **Sortir d'un `try` émet un `POP_TRY` par bloc quitté** (`pop_crossed_tries` pour
  `break`/`continue`, la même boucle dans `visit(ReturnStmt)` pour `return`). Sans cela le
  gestionnaire restait empilé : une erreur survenue longtemps après la boucle était interceptée
  par lui, et le `catch` s'exécutait une fois par tour effectué. Pour `return`, le compte part du
  **plancher de la fonction** (`try_floors_`, empilé avec `outer_scopes_`), un `return` ne
  quittant que les `try` de SA fonction.
- ⚠ **Pourquoi côté compilateur et non côté VM** : dépiler les gestionnaires morts à chaque
  `RETURN` (le `Handler` porte déjà `call_depth`) coûte **+1,23 % d'instructions sur
  `bench_fib`**, mesuré — pour un test inutile en l'absence de `try`. La version compilateur
  mesure **+0,00 %**.

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
