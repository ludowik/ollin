---
name: code-review
description: Revue de code du diff en cours — correction, appels manqués, invariants du projet, tests manquants, textes devenus faux. Lit le contexte hors du diff, reproduit les bugs avant de les signaler, puis corrige. Vise automatiquement le bon périmètre — modifications non commitées, sinon TOUS les commits depuis la dernière revue (repère git local refs/reviewed), sinon le dernier commit. Se lance sans argument.
---

`effort moyen → diff + contexte lu → constats reproduits → classés, sans plafond → corrections`

La qualité du code (réutilisation générale, simplification, efficacité, altitude) reste à `/simplify` :
cette revue répond à « est-ce que ça marche, et est-ce que tout le reste est resté d'accord avec ? ».

## Turn 1 — déterminer la cible PUIS lire le diff (un seul appel outil)

Algorithme de résolution partagé avec `/simplify` — voir
`.claude/skills/_shared/review-target.md`. Repère de CETTE passe : `refs/reviewed`
(distinct de `refs/simplified`, propre à `/simplify` — les deux passes sont
indépendantes, correctness pour l'une, qualité pour l'autre).

Lire le diff résolu en UN appel. Ne pas lire les hunks de test/fixture
(`tests/`, `test/`, `*_test.*`, `*.test.*`, `fixtures/`, `testdata/`) ni les artefacts de build
(`docs/wasm/`, dates de build) — mais **relever les NOMS** des fichiers de test que le diff touche
(`git diff --stat`), le Turn 3 en a besoin.

## Turn 2 — lire le contexte HORS du diff

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
   contexte montre que la valeur peut manquer, garde retirée, test de véracité sur une valeur qui
   peut valoir 0, `await` manquant, copier-coller de mauvaise variable, erreur avalée dans un `catch`
   qui devrait propager, état périmé (une valeur lue trop tôt, jamais rafraîchie).
2. **Sites manqués** : un changement de règle ou de helper (Turn 2) que tous les appelants n'ont pas
   suivi.
3. **Invariants du projet** : la liste de `.claude/skills/_shared/project-invariants.md`, la section
   qui correspond aux fichiers du diff (`src/`, `docs/`, `.ol`). Ne signaler qu'une violation
   RÉELLE du code lu.
4. **Tests** : un bug corrigé, un comportement nouveau ou un refus nouveau SANS test dans le bon
   fichier — la FORME dans `tests/syntax.ol`, le COMPORTEMENT dans `tests/regressions.ol`, l'ÉCHEC dans
   `tests/test_errors.sh` (cf. CLAUDE.md). Un diff qui ne touche aucun fichier de test alors qu'il change
   un comportement est un constat.
5. **Textes devenus faux** : un commentaire, une ligne du tutoriel, de `grammar.ebnf` ou de CLAUDE.md
   que le diff rend inexacte (un champ qui n'existe plus, une règle inversée). Pas de rédaction
   propre à un EXEMPLE dans CLAUDE.md (cf. sa règle d'entrée).
6. **Duplication et code mort** vus dans le diff : du code neuf qui recopie un helper visible, une
   constante, un champ ou une fonction que plus rien n'appelle.

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

## Turn 5 — un regard neuf, quand le diff le vaut

Celui qui relit son propre travail garde ses angles morts. Si le diff touche le moteur (`src/`), le
routeur ou un module partagé de `docs/lib/`, ou dépasse environ 300 lignes hors tests, lancer UN agent
en lecture seule qui ne reçoit **que** le diff (pas la conversation, pas les intentions) et les angles
1 et 2 du Turn 3, avec l'ordre de ne rien modifier. Fondre ses constats avec les vôtres, en les
reproduisant de la même façon. Sinon, passer.

## Sortie

Les constats du plus grave au moins grave, **sans plafond**, une ligne chacun :

`chemin/fichier.ext:123 — ce qui ne va pas et l'échec concret [reproduit|probable]`

Si rien ne qualifie, sortir `(none)`. Ajouter ensuite, quand quelque chose a été examiné sérieusement
puis écarté, une ligne par écart : `écarté — chemin:ligne — pourquoi ce n'est pas un défaut`. Réponse
**en français**, en texte lisible (règle projet). Ne pas appeler l'outil ReportFindings même s'il est
disponible.

## Turn 6 — CORRIGER, sans demander

Une revue se termine par les corrections, pas par une question. Appliquer chaque
constat immédiatement — recompiler, lancer `bash tests/run.sh`, committer, pousser
— puis dire en une phrase ce qui a été corrigé. Ne JAMAIS écrire « veux-tu que je
corrige ? » : la réponse est toujours oui, et la poser fait perdre un tour.

Un défaut de comportement corrigé **se fige dans un test** (le bon fichier, cf. Turn 3.4) : c'est ce
qui distingue une revue d'une opinion. Un texte devenu faux se corrige avec le code qui l'a rendu faux.

Seule exception : un constat dont la correction changerait un comportement voulu,
ou déborderait largement du périmètre revu. Le dire alors en une ligne, et
corriger tout le reste.

## Après la revue — avancer le repère

Règle partagée (`.claude/skills/_shared/review-target.md`), appliquée à
`refs/reviewed`.
