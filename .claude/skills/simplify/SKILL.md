---
name: simplify
description: Revue de QUALITÉ du code modifié — réutilisation, simplification, efficacité, altitude — suivie des corrections. Ne cherche pas les bugs de correctness : c'est le rôle de /code-review. Se lance sans argument.
---

`4 agents en parallèle → dédoublonnage → corrections appliquées`

Version PROJET du skill fourni. Elle en garde les quatre angles et y ajoute ce que le
dépôt impose : réponse en français, corrections appliquées sans demander, suite de tests
avant commit.

## Phase 0 — le diff à revoir

Un repère git LOCAL `refs/simplified` marque le dernier état déjà passé en revue de
qualité — distinct de `refs/reviewed` (`/code-review`) : les deux passes sont
indépendantes (correctness pour l'une, qualité pour l'autre), et les confondre ferait
avancer l'une sans que l'autre ait jamais eu lieu.

Résoudre la cible dans cet ordre, s'arrêter à la première non vide :
1. argument explicite (numéro de PR, branche, chemin) ;
2. `git diff HEAD` (modifications non commitées) — la revue précède souvent le commit ;
3. si la ref existe (`git rev-parse --verify --quiet refs/simplified`) :
   `git diff refs/simplified..HEAD` — tous les commits depuis la dernière passe qualité,
   quel qu'en soit le nombre (un rebuild WASM intercalé, ou plusieurs fonctionnalités
   enchaînées sans repasser par `/simplify`, ne masquent donc rien) ;
4. sinon `git diff @{upstream}...HEAD` (ou `main...HEAD` sans upstream) ;
5. sinon `git diff HEAD~1..HEAD` — dernier commit (première passe du conteneur : le
   repère n'existe pas encore).

## Phase 1 — quatre agents en parallèle

Lancer **quatre** agents indépendants dans un SEUL message, pour qu'ils travaillent en même
temps. Chacun reçoit le diff et un angle. Chacun rend ses constats avec `file`, `line`, une
ligne de résumé, et le coût concret — ce qui est dupliqué, gaspillé, ou plus difficile à
maintenir.

**Réutilisation.** Du code neuf qui réimplémente ce que le dépôt a déjà. Chercher dans les
utilitaires partagés et les fichiers voisins, et NOMMER l'existant à appeler.

**Simplification.** La complexité que le diff ajoute : état redondant ou déductible,
copier-coller avec variation, imbrication profonde, code mort laissé derrière. Nommer la
forme plus simple qui fait le même travail.

**Efficacité.** Le travail gaspillé : calcul refait, entrées-sorties répétées, opérations
indépendantes exécutées en série, travail bloquant ajouté au démarrage ou à un chemin chaud.
Signaler aussi les objets à longue vie construits sur une fermeture, qui retiennent toute la
portée englobante.

**Altitude.** Chaque changement est-il fait à la bonne profondeur, ou est-ce un pansement ?
Des cas particuliers empilés sur une infrastructure partagée signalent un correctif trop
superficiel : généraliser le mécanisme vaut mieux qu'ajouter une exception.

## Phase 2 — CORRIGER, sans demander

Attendre les quatre agents, dédoublonner les constats qui visent la même ligne ou le même
mécanisme, puis **corriger chacun** — recompiler, lancer `bash tests/run.sh`, committer,
pousser. Ne JAMAIS écrire « veux-tu que je corrige ? » : la réponse est toujours oui, et la
poser fait perdre un tour (règle permanente, cf. CLAUDE.md).

Un constat peut être écarté s'il changerait un comportement voulu, s'il déborde largement du
diff revu, ou s'il est un faux positif. Le dire alors en une ligne, sans argumenter, et
corriger tout le reste.

Terminer par un résumé bref : ce qui a été corrigé, ce qui a été écarté et pourquoi — en
**texte lisible**, jamais un dump de structure de données (règle projet).

## Après la revue — avancer le repère

Si la cible retenue était un **intervalle commité** (cas 3, 4 ou 5), poser le repère sur
l'état revu : `git update-ref refs/simplified HEAD`. Ainsi la prochaine passe repart de
là. Ne PAS l'avancer pour un argument explicite (cas 1) ni des modifications non commitées
(cas 2) — les commits non encore passés en revue doivent rester en attente. À faire même
si aucun constat n'a été retenu (l'état a bien été revu).
