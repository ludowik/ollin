---
name: simplify
description: Revue de QUALITÉ du code — réutilisation, simplification, efficacité, altitude — suivie des corrections. Sans argument (ou avec une référence git) c'est le diff ; avec un chemin, un dossier ou un nom de module (tween, ui, docs/samples/blockudoku/) c'est une lecture COMPLÈTE de ce code, hors diff. Ne cherche pas les bugs de correctness : c'est le rôle de /code-review.
---

`4 agents en parallèle → dédoublonnage → corrections appliquées`

Version PROJET du skill fourni. Elle en garde les quatre angles et y ajoute ce que le
dépôt impose : réponse en français, corrections appliquées sans demander, suite de tests
avant commit.

## Le mode se lit dans l'argument

Même table que `/code-review` (voir `.claude/skills/code-review/SKILL.md`, « Le mode se lit dans
l'argument ») : aucun argument, un intervalle git ou une référence seule → **diff** ; un chemin de
fichier ou de dossier, ou un nom de module → **module**.

## Phase 0 — le périmètre

### Mode diff

Algorithme de résolution partagé avec `/code-review` — voir
`.claude/skills/_shared/review-target.md`. Repère de CETTE passe : `refs/simplified`
(distinct de `refs/reviewed`, propre à `/code-review` — les deux passes sont
indépendantes, correctness pour l'une, qualité pour l'autre).

### Mode module

Aucun diff n'est lu, `refs/simplified` n'est ni consulté ni avancé. Résoudre l'argument comme le
mode module de `/code-review` (« Turn 1 », y compris les fichiers frères d'un nom court : en-tête,
stub, frontière interne) et lire ces fichiers **en entier**. Chaque agent reçoit la liste des
fichiers, pas un diff.

## Phase 1 — quatre agents en parallèle

Lancer **quatre** agents indépendants dans un SEUL message, pour qu'ils travaillent en même
temps. Chacun reçoit le diff (mode module : la liste des fichiers) et un angle. Chacun rend ses constats avec `file`, `line`, une
ligne de résumé, et le coût concret — ce qui est dupliqué, gaspillé, ou plus difficile à
maintenir.

**Réutilisation.** Du code neuf (mode module : du code) qui réimplémente ce que le dépôt a déjà. Chercher dans les
utilitaires partagés et les fichiers voisins, et NOMMER l'existant à appeler.

**Simplification.** La complexité que le diff ajoute (mode module : que le code porte) : état redondant ou déductible,
copier-coller avec variation, imbrication profonde, code mort laissé derrière. Nommer la
forme plus simple qui fait le même travail.

**Efficacité.** Le travail gaspillé (mode module : sur les chemins chauds du module — la boucle de
frame, les appels répétés —, sans chercher une lenteur supposée ailleurs) : calcul refait, entrées-sorties répétées, opérations
indépendantes exécutées en série, travail bloquant ajouté au démarrage ou à un chemin chaud.
Signaler aussi les objets à longue vie construits sur une fermeture, qui retiennent toute la
portée englobante.

**Altitude.** Chaque changement est-il fait à la bonne profondeur, ou est-ce un pansement ? (Mode
module : le module est-il à la bonne profondeur, et chaque morceau de ses fichiers dans le bon
fichier ?)
Des cas particuliers empilés sur une infrastructure partagée signalent un correctif trop
superficiel : généraliser le mécanisme vaut mieux qu'ajouter une exception.

## Phase 2 — CORRIGER, sans demander

Attendre les quatre agents, dédoublonner les constats qui visent la même ligne ou le même
mécanisme, puis **corriger chacun** — recompiler, lancer `bash tests/run.sh`, committer,
pousser. Ne JAMAIS écrire « veux-tu que je corrige ? » : la réponse est toujours oui, et la
poser fait perdre un tour (règle permanente, cf. CLAUDE.md).

Un constat peut être écarté s'il changerait un comportement voulu, s'il déborde largement du
périmètre revu (le diff, ou en mode module une réécriture du module), ou s'il est un faux positif. Le dire alors en une ligne, sans argumenter, et
corriger tout le reste.

Terminer par un résumé bref : ce qui a été corrigé, ce qui a été écarté et pourquoi — en
**texte lisible**, jamais un dump de structure de données (règle projet).

## Après la revue — avancer le repère

- **Mode diff** : règle partagée (`.claude/skills/_shared/review-target.md`), appliquée à
  `refs/simplified`.
- **Mode module** : le repère n'est jamais avancé — les commits non encore passés en revue en
  mode diff restent en attente.
