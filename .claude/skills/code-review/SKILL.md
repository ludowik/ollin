---
name: code-review
description: Revue de code bas-effort du diff en cours. Vise automatiquement le bon périmètre — modifications non commitées, sinon TOUS les commits depuis la dernière revue (repère git local refs/reviewed), sinon le dernier commit. Se lance sans argument.
---

`low effort → 1 diff pass → no verify → ≤4 findings`

## Turn 1 — déterminer la cible PUIS lire le diff (un seul appel outil)

Un repère git LOCAL `refs/reviewed` marque le dernier état déjà revu. Il est
local au conteneur : une nouvelle session repart d'un clone frais sans ce repère
(repli sur le dernier commit, puis le mécanisme se ré-amorce).

Résoudre la cible dans cet ordre, s'arrêter à la première non vide :
1. argument explicite passé à la commande, s'il y en a un ;
2. `git diff HEAD` (modifications non commitées) — revue du WIP ;
3. si la ref existe (`git rev-parse --verify --quiet refs/reviewed`) :
   `git diff refs/reviewed..HEAD` — **TOUS les commits depuis la dernière revue**,
   quel qu'en soit le nombre. C'est le cas NORMAL : la règle projet impose de
   committer **et pousser** sur `main` après chaque feature, et une reprise de
   session réaligne `@{upstream}` sur `origin/main` → sans repère on ne verrait
   que le dernier commit ; `refs/reviewed` accumule l'ensemble non encore revu ;
4. `git diff @{upstream}...HEAD` (commits en avance sur l'upstream) ;
5. **sinon `git diff HEAD~1..HEAD`** — le dernier commit (première revue du
   conteneur : le repère n'existe pas encore). Ne jamais conclure « rien à
   réviser » sans avoir essayé HEAD~1..HEAD.

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

## Après la revue — avancer le repère

Si la cible retenue était un **intervalle commité** (cas 3, 4 ou 5), poser le
repère sur l'état revu : `git update-ref refs/reviewed HEAD`. Ainsi la prochaine
revue repart de là. Ne PAS l'avancer pour une revue d'argument explicite (cas 1)
ni de modifications non commitées (cas 2) — les commits non encore revus doivent
rester en attente. À faire même si le verdict est `(none)` (l'état a bien été revu).
