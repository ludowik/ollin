---
name: code-review
description: Revue de code, en deux modes. Sans argument (ou avec une référence git) c'est le diff — modifications non commitées, sinon TOUS les commits depuis la dernière revue (repère refs/reviewed), sinon le dernier commit. Avec un chemin, un dossier ou un nom de module (tween, ui, src/modules/ui_module.cpp, docs/samples/blockudoku/) c'est une lecture COMPLÈTE de ce code, hors diff. Cherche la correction, les appels manqués, les invariants du projet, les tests manquants, les textes faux ; lit le contexte, reproduit avant de signaler, puis corrige.
---

`effort moyen → périmètre lu → constats reproduits → classés, sans plafond → corrections`

La qualité du code (réutilisation générale, simplification, efficacité, altitude) reste à `/simplify` :
cette revue répond à « est-ce que ça marche, et est-ce que tout le reste est resté d'accord avec ? ».

## Le mode se lit dans l'argument

| Argument | Mode | Périmètre |
|---|---|---|
| aucun | **diff** | la cible de l'algorithme partagé (modifications en attente, sinon depuis la dernière revue, sinon le dernier commit) |
| un intervalle git (`HEAD~3..HEAD`, `main..HEAD`) | **diff** | exactement cet intervalle |
| une référence seule (`HEAD~3`, `a1b2c3d`) | **diff** | `<réf>..HEAD` : les commits écrits depuis elle (jamais `git diff <réf>` nu, qui y ajouterait les modifications non commitées) |
| un chemin de fichier ou de dossier, ou un nom de module (`tween`, `ui`, `sound`, `graphics`…) | **module** | ces fichiers, lus EN ENTIER, que le code date du dernier commit ou d'il y a six mois |

Un argument qui n'est ni une référence git valide (`git rev-parse --verify`) ni un chemin existant ni
un nom de module : le dire en une ligne et demander ce qui est visé.

## Turn 1 — établir le périmètre

### Mode diff

Algorithme de résolution partagé avec `/simplify` — voir
`.claude/skills/_shared/review-target.md`. Repère de CETTE passe : `refs/reviewed`
(distinct de `refs/simplified`, propre à `/simplify` — les deux passes sont
indépendantes, correctness pour l'une, qualité pour l'autre).

Lire le diff résolu en UN appel. Ne pas lire les hunks de test/fixture
(`tests/`, `test/`, `*_test.*`, `*.test.*`, `fixtures/`, `testdata/`) ni les artefacts de build
(`docs/wasm/`, dates de build) — mais **relever les NOMS** des fichiers de test que le diff touche
(`git diff --stat`), le Turn 3 en a besoin.

### Mode module

Aucun diff n'est lu, `refs/reviewed` n'est ni consulté ni avancé. Résoudre l'argument :

- un chemin de fichier → ce fichier ;
- un dossier → tous ses fichiers de code ;
- un nom court (`ui`, `tween`, `sound`, `graphics`, `touch`, `image`, `data`…) →
  `src/modules/<nom>_module.cpp` **plus** tout fichier frère du même préfixe : en-tête
  (`<nom>_module.h`), stub (`<nom>_stub.cpp`), frontière interne (`<nom>_internal.h`), fichiers éclatés
  (`graphics3d.cpp`, `graphics_quat.cpp`, `sound_output*.cpp`). Un module se juge avec sa frontière.

Lire ces fichiers **en entier**. Puis, en un seul appel de recherche, relever les **appelants** hors du
module (`grep` du nom des fonctions exposées et des symboles de la frontière) : beaucoup de défauts
d'un module natif ne sont visibles que du côté de son appelant — un `reset` jamais appelé, un rappel
invoqué au mauvais moment de la frame, un handle gardé à travers un appel Ollin.

## Turn 2 — lire le contexte HORS du périmètre (mode diff)

En mode module, les appelants du Turn 1 en tiennent lieu : passer au Turn 3.

Un hunk ne montre pas l'état qu'il laisse derrière lui. Pour chaque symbole que le diff ajoute ou
change (fonction, champ, constante, nom exporté, drapeau) :

- **ses autres usages**, en une recherche (`grep` du nom) : un site qui n'a pas suivi le changement
  est le défaut le plus fréquent d'un remaniement (un helper partagé que l'on remplace partout
  sauf à un endroit) ;
- **les fonctions qui touchent le même état** : lire le corps ENTIER de celles que le hunk ne montre
  qu'en partie, et de celles qui écrivent le même champ (une borne relue au démarrage d'une étape,
  mais mise en réserve à la construction : le bug n'était visible que dans la fonction voisine).

Rester ciblé : des recherches et des corps de fonction, pas des fichiers entiers.

## Turn 3 — ce qu'on cherche

Dans cet ordre de gravité :

1. **Correction** : condition inversée ou fausse, off-by-one, déréférencement nul/absent quand le
   contexte montre que la valeur peut manquer, garde retirée ou absente, test de véracité sur une
   valeur qui peut valoir 0, `await` manquant, copier-coller de mauvaise variable, erreur avalée dans
   un `catch` qui devrait propager, valeur non initialisée, débordement d'un tableau de taille fixe,
   état périmé (une valeur lue trop tôt, jamais rafraîchie).
2. **Sites manqués** (mode diff) : un changement de règle ou de helper (Turn 2) que tous les appelants
   n'ont pas suivi.
3. **Invariants du projet** : la liste de `.claude/skills/_shared/project-invariants.md`, la section
   qui correspond aux fichiers relus (`src/`, `docs/`, `.ol`). Ne signaler qu'une violation RÉELLE du
   code lu.
4. **Tests** :
   - mode diff : un bug corrigé, un comportement nouveau ou un refus nouveau SANS test dans le bon
     fichier — la FORME dans `tests/syntax.ol`, le COMPORTEMENT dans `tests/regressions.ol`, l'ÉCHEC dans
     `tests/test_errors.sh` (cf. CLAUDE.md). Un diff qui change un comportement du moteur, de la web app ou
     d'un exemple sans toucher un fichier de test est un constat (pas un diff de documentation ou de consignes) ;
   - mode module : seulement un cas non couvert qui EXPLIQUE un constat.
5. **Textes devenus faux** : un commentaire, une ligne du tutoriel, de `grammar.ebnf` ou de CLAUDE.md
   que le diff (ou, en mode module, le code lu) contredit — un champ qui n'existe plus, une règle
   inversée. Pas de rédaction propre à un EXEMPLE dans CLAUDE.md (cf. sa règle d'entrée).
6. **Duplication et code mort** : du code qui recopie un helper visible, une validation recopiée entre le
   module et son stub au lieu de vivre dans l'en-tête partagé, une constante, un champ, une fonction ou
   une branche que plus aucun appelant n'atteint.

Ne PAS signaler le style, le nommage local, la performance supposée sans mesure.

## Turn 4 — PROUVER avant de signaler

Un constat de correction doit montrer son échec. Quand c'est peu coûteux, le **reproduire** : quelques
lignes d'Ollin lancées par `./build/ollin`, un script Playwright (cf. CLAUDE.md, chaîne B), un appel dans
la suite de tests. Écrire ces essais dans le répertoire temporaire de la session, **jamais dans le
dépôt**. Marquer chaque constat :

- `[reproduit]` — l'échec a été vu ;
- `[probable]` — il suit du code lu mais n'a pas été exécuté (plateforme hors d'atteinte : un vrai
  iPhone, un événement que le harnais ne produit pas).

Un constat sans échec concret n'est PAS un constat : il tombe.

## Turn 5 — un regard neuf, quand le périmètre le vaut

Celui qui relit son propre travail garde ses angles morts. Si le périmètre touche le moteur (`src/`), le
routeur ou un module partagé de `docs/lib/`, ou dépasse environ 300 lignes de diff hors tests (mode
diff) ou 800 lignes lues (mode module), lancer UN agent en lecture seule qui ne reçoit **que** le
diff ou la liste des fichiers (pas la conversation, pas les intentions) et les angles 1 et 2 du
Turn 3, avec l'ordre de ne rien modifier. Fondre ses constats avec les vôtres, en les reproduisant de la
même façon. Sinon, passer.

## Sortie

Les constats du plus grave au moins grave, **sans plafond**, une ligne chacun :

`chemin/fichier.ext:123 — ce qui ne va pas et l'échec concret [reproduit|probable]`

Si rien ne qualifie, sortir `(none)` — et le dire sans chercher à remplir. Ajouter ensuite, quand
quelque chose a été examiné sérieusement puis écarté, une ligne par écart :
`écarté — chemin:ligne — pourquoi ce n'est pas un défaut`. Réponse **en français**, en texte lisible
(règle projet). Ne pas appeler l'outil ReportFindings même s'il est disponible.

## Turn 6 — CORRIGER, sans demander

Une revue se termine par les corrections, pas par une question. Appliquer chaque
constat immédiatement — recompiler, lancer `bash tests/run.sh`, committer, pousser
— puis dire en une phrase ce qui a été corrigé. Ne JAMAIS écrire « veux-tu que je
corrige ? » : la réponse est toujours oui, et la poser fait perdre un tour.

Un défaut de comportement corrigé **se fige dans un test** (le bon fichier, cf. Turn 3.4) : c'est ce
qui distingue une revue d'une opinion. Un texte devenu faux se corrige avec le code qui l'a rendu faux.

Seule exception : un constat dont la correction changerait un comportement voulu, ou déborderait
largement du périmètre revu (en mode module : demanderait de réécrire le module). Le dire alors en une
ligne, et corriger tout le reste.

## Après la revue — avancer le repère

- **Mode diff**, cible résolue par l'algorithme (modifications en attente exclues) : règle partagée
  (`.claude/skills/_shared/review-target.md`), appliquée à `refs/reviewed`. Un diff désigné par une
  référence explicite n'avance PAS le repère.
- **Mode module** : le repère n'est jamais avancé — les commits non encore revus en mode diff restent
  en attente.
