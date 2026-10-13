---
name: audit
description: Passe complète sur un module ou un dossier — /code-review, puis /simplify, puis /code-review de contrôle si la simplification a modifié du code. Prend un chemin, un dossier ou un nom de module (tween, ui, docs/samples/blockudoku/). Chaîne les trois passes à la place de l'utilisateur ; ne contient aucune règle de revue propre.
---

`code-review → simplify → code-review (si simplify a modifié du code)`

Ce skill ne fait que **l'enchaînement**. Les règles de chaque passe — périmètre, angles, preuves,
corrections, repères — vivent dans `.claude/skills/code-review/SKILL.md` et
`.claude/skills/simplify/SKILL.md` : ne rien en recopier ici, deux textes finissent toujours par
diverger.

## Argument

Obligatoire : un chemin de fichier ou de dossier, ou un nom de module — le **mode module** des deux
skills. Sans argument, ou avec un intervalle git, ce n'est pas un audit : le dire en une ligne et
proposer `/code-review` et `/simplify` séparément (ils savent revoir un diff).

## Ordre, et pourquoi

1. **`/code-review <argument>`** — d'abord, parce qu'une simplification faite sur du code faux
   l'enracine. Ses constats sont corrigés, testés, commités et poussés (règle propre au skill).
2. **`/simplify <argument>`** — sur le code désormais correct. Mêmes règles de correction.
3. **`/code-review <argument>`** de contrôle — **seulement si l'étape 2 a modifié du code** : une
   simplification est un remaniement, donc la source d'un défaut possible. Si elle n'a rien changé
   (ou n'a trouvé que du texte), passer.

Invoquer chaque passe par l'outil Skill avec l'argument tel quel, et ne passer à la suivante qu'une
fois la précédente terminée (corrections poussées comprises) : la suivante doit lire l'état corrigé.

## Sortie

Un seul rapport final, en français et en texte lisible : par passe, ce qui a été corrigé et ce qui a
été écarté (une ligne chacun), puis l'état final (`bash tests/run.sh` vert, commits poussés). Ne pas
répéter in extenso les rapports intermédiaires.

Aucun repère n'avance : le mode module n'en touche aucun.
