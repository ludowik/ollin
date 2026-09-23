---
name: code-review
description: Revue de code bas-effort du diff en cours. Vise automatiquement le bon périmètre — modifications non commitées, sinon TOUS les commits depuis la dernière revue (repère git local refs/reviewed), sinon le dernier commit. Se lance sans argument.
---

`low effort → 1 diff pass → no verify → ≤4 findings`

## Turn 1 — déterminer la cible PUIS lire le diff (un seul appel outil)

Algorithme de résolution partagé avec `/simplify` — voir
`.claude/skills/_shared/review-target.md`. Repère de CETTE passe : `refs/reviewed`
(distinct de `refs/simplified`, propre à `/simplify` — les deux passes sont
indépendantes, correctness pour l'une, qualité pour l'autre).

Lire le diff résolu en UN appel. Sauter les hunks de test/fixture
(`tests/`, `test/`, `*_test.*`, `*.test.*`, `fixtures/`, `testdata/`) et les
artefacts de build (`docs/wasm/`, dates de build). Pas de sous-agent, pas de
lecture de fichiers entiers.

## Turn 2 — findings

Signaler uniquement les bugs de correctness visibles depuis le hunk seul :
condition inversée/fausse, off-by-one, déréférencement nul/absent quand les
lignes voisines montrent que la valeur peut manquer, garde retirée, test falsy
sur zéro, `await` manquant, copier-coller de mauvaise variable, erreur avalée
dans un catch qui devrait propager. Signaler aussi, toujours depuis le hunk
seul, le code neuf qui duplique un helper visible dans le contexte du diff, et
le code mort laissé derrière.

Ne PAS signaler style, nommage, perf, tests manquants, ni rien hors du hunk.

Sortir au plus **4 findings**, du plus grave au moins grave, une ligne chacun :
`chemin/fichier.ext:123 — ce qui ne va pas et l'échec concret`. Si rien ne
qualifie, sortir exactement `(none)`. Réponse **en français** (règle projet).
Ne pas appeler l'outil ReportFindings même s'il est disponible.

## Turn 3 — CORRIGER, sans demander

Une revue se termine par les corrections, pas par une question. Appliquer chaque
finding immédiatement — recompiler, lancer `bash tests/run.sh`, committer, pousser
— puis dire en une phrase ce qui a été corrigé. Ne JAMAIS écrire « veux-tu que je
corrige ? » : la réponse est toujours oui, et la poser fait perdre un tour.

Seule exception : un finding dont la correction changerait un comportement voulu,
ou déborderait largement du périmètre revu. Le dire alors en une ligne, et
corriger tout le reste.

## Après la revue — avancer le repère

Règle partagée (`.claude/skills/_shared/review-target.md`), appliquée à
`refs/reviewed`.
