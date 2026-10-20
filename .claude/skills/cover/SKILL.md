---
name: cover
description: Couverture de lignes du moteur par la suite de tests — lance tools/coverage.sh, rend un tableau de synthèse (langage, modules), dit ce qui est faible et quelles lignes ne s'exécutent jamais. Sans argument, le rapport global ; avec un fichier ou un module (data, color, src/vm.cpp), les lignes non exécutées de celui-là.
---

`tools/coverage.sh → tableau de synthèse → lecture → lignes non exécutées des fichiers faibles → pistes de tests`

Ce skill LIT la couverture, il n'écrit aucun test : proposer où les mettre, attendre le GO (règle
« plan ⇒ pas d'implémentation sans GO » de `CLAUDE.md`). La section « Couverture » de `CLAUDE.md`
reste la référence de ce que la mesure vaut.

## Phase 1 — la mesure

`bash tools/coverage.sh --check` depuis la racine. Une minute et demie au premier passage du
conteneur (compilation instrumentée dans `build-cov/`), une demi-minute ensuite. Le script rend le
tableau par fichier (moins couvert d'abord), le total, une section `SYNTHESIS` (le langage par
étage, puis les modules un par un, les stubs sur une ligne), et échoue sous le plancher de
`tools/coverage-floor`.

Ne jamais lancer `--floor` de sa propre initiative : relever le plancher engage le dépôt. Le
PROPOSER quand le total a monté durablement, et attendre.

## Phase 2 — le tableau de synthèse, puis la lecture

Le livrable commence par **un tableau de synthèse** : celui de la section `SYNTHESIS` du script,
recopié en tableau Markdown (colonnes : zone, lignes, non exécutées, couverture), en deux blocs.
C'est le seul tableau à rendre ; le tableau par fichier du script n'est jamais collé.

- **Langage** : une ligne par étage (lexer, parser, compilateur, VM, collections, chemins et
  sources, point d'entrée) et un sous-total.
- **Modules** : une ligne par module, une ligne « stubs » à part (un 0 % y est ATTENDU, `graphics`
  étant nil dans le build headless) et un sous-total **sans** les stubs.
- Sous le tableau, deux lignes qui complètent le chiffre, tirées des gardes (elles durent moins
  d'une seconde) : `bash tests/check_grammar_coverage.sh` (règles de la grammaire citées par
  `syntax.ol`) et `bash tests/check_api_coverage.sh` (fonctions exposées nommées par un test).
  Ce sont des couvertures de NOMS, pas de lignes : le dire.
- Une colonne ou une note « évolution » seulement si l'état précédent est connu (relevé de la
  même session, ou le chiffre de `CLAUDE.md`), et en nommant la base de comparaison.

Puis un compte rendu en français, en prose et listes :

- le total, le plancher, et si le contrôle passe ;
- les zones sous 90 %, en trois familles :
  1. **les modules de `src/modules/`** (`data`, `color`, `core`, `sound`…) : ce sont eux la cible ;
  2. **le cœur** (`vm.cpp`, `compiler.cpp`, `parser.cpp`, `lexer.cpp`, `paths.cpp`,
     `source_registry.cpp`, `collections/`) ;
  3. **les stubs** (`*_stub.cpp`, `graphics_stub`, `image_stub`, `camera_stub`) : les signaler une
     fois, ne pas les compter parmi les faiblesses.
- ce que la mesure ne voit pas : les vrais modules graphiques (`graphics`, `image`, `camera`,
  `mouse`, `keyboard`) ne sont pas compilés en headless, donc absents du chiffre.

## Phase 3 — les lignes qui ne s'exécutent jamais

Pour chaque fichier faible (ou celui que l'utilisateur a nommé : `data` → `src/modules/data_module.cpp`) :

```bash
mkdir -p /tmp/cover-gcov && cd /tmp/cover-gcov
gcov -o <racine>/build-cov/CMakeFiles/ollin.dir/src/modules \
     <racine>/build-cov/CMakeFiles/ollin.dir/src/modules/data_module.cpp.gcda >/dev/null 2>&1
grep -E '^\s+#####:' data_module.cpp.gcov
```

(`src/` seul pour un fichier du cœur : le dossier d'objets est `…/ollin.dir/src`.) Toujours dans un
répertoire temporaire, **jamais dans le dépôt** : `gcov` écrit ses `.gcov` dans le répertoire courant.

Lire les lignes **avec leur contexte** avant de conclure : la plupart des trous sont des chemins
d'ERREUR (un `throw`) ou des cas limites, rarement une fonctionnalité entière. Les regrouper par
nature plutôt que de les lister une à une :
- un message d'erreur jamais déclenché → `tests/test_errors.sh` ;
- un cas limite d'une valeur (échappement, flottant, bord) → `tests/regressions/modules/<module>.ol` ;
- une branche d'une fonction du langage → `tests/regressions/language/<domaine>.ol`.

## Garde-fous de lecture

- **Une ligne exécutée n'est pas une ligne vérifiée.** Seule une mutation (casser la ligne, voir la
  suite échouer) le prouve. Ne pas présenter un pourcentage comme une garantie.
- Les en-têtes sont exclus du chiffre (leur code en ligne est compté par unité de compilation).
- Ne jamais comparer deux relevés faits sur des états différents du dépôt sans le dire.
