---
name: code-review
description: Revue de code bas-effort du diff en cours. Vise automatiquement le bon périmètre — modifications non commitées / en avance sur l'upstream, sinon (rien en attente, cas normal car on pousse toujours sur main) le dernier commit HEAD~1..HEAD. Se lance sans argument.
---

`low effort → 1 diff pass → no verify → ≤4 findings`

## Turn 1 — déterminer la cible PUIS lire le diff (un seul appel outil)

Résoudre la cible dans cet ordre, s'arrêter à la première non vide :
1. argument explicite passé à la commande, s'il y en a un ;
2. `git diff HEAD` (modifications non commitées) ;
3. `git diff @{upstream}...HEAD` (commits en avance sur l'upstream) ;
4. **sinon `git diff HEAD~1..HEAD`** — le dernier commit. C'est le cas NORMAL
   ici : la règle projet impose de committer **et pousser** sur `main` après
   chaque feature, et une reprise de session réaligne `@{upstream}` sur
   `origin/main` → les cibles 2 et 3 sont vides alors qu'il y a bien du travail
   à réviser. Ne jamais conclure « rien à réviser » sans avoir essayé HEAD~1..HEAD.

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
