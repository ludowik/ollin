---
name: perf
description: Relevé de performances complet — temps (bench/bench_all.sh) ET travail (bench/icount.sh), publiés dans la vue #/perf. Se lance sans argument ; RUNS=N pour changer le nombre d'exécutions.
---

`temps + instructions → publication dans #/perf → commit`

C'est le mot-clé **perf** de `CLAUDE.md`, rendu invocable. La section « Commande `perf` » de
`CLAUDE.md` reste la référence : ce fichier ne fait que l'exécuter dans l'ordre.

## Phase 1 — le TEMPS

`bash bench/bench_all.sh` (ou `RUNS=5 bash bench/bench_all.sh` si l'utilisateur donne un nombre).

Ce que le script fait déjà, et qu'il ne faut pas refaire à la main : il localise seul les
interpréteurs, lance chaque benchmark **RUNS fois** (3 par défaut) et garde le **meilleur** temps,
mesure le temps **PROCESSEUR** dans les trois langages, et affiche une somme de contrôle par
benchmark. Une colonne à `N/A` signifie qu'un interpréteur manque — le dire, ne pas le contourner.
Si `lua5.4` manque, `sudo apt-get install -y lua5.4` suffit ; **ne jamais compiler Lua depuis les
sources** (`lua.org` est bloqué par le proxy).

## Phase 2 — le TRAVAIL

`bash bench/icount.sh` — compte d'instructions exécutées (callgrind), déterministe et indifférent
à l'adresse du code comme au cache. C'est la seule mesure qui distingue un coût réel d'un effet de
disposition.

## Phase 3 — publier

Deux fichiers, deux natures opposées, ne pas les confondre :

- **`docs/data/bench-snapshot.json` est REMPLACÉ**, jamais complété. Un temps ne vaut que pour une
  machine et un moment, donc une série historique de temps n'aurait aucun sens. Le fichier porte
  `date`, `commit`, `runs`, `machine`, `build` — un relevé sans son contexte serait trompeur —
  puis la référence Lua et les concurrents. Relever le contexte pour de vrai :
  `git rev-parse --short HEAD`, `date -I`, `lscpu | grep -E "Model name|^CPU\(s\)"`,
  `g++ --version`. Garder le champ `_` d'en-tête, qui explique le fichier à qui l'ouvre.
- **`docs/data/icount-history.json` s'ALLONGE** : ajouter un jalon à `milestones`. Garder le
  champ `_`, `tool`, `machine` et `scripts` tels quels.

La vue `#/perf` lit les deux et reste valide si l'un manque (sa section disparaît).

## Phase 4 — rendre compte, puis committer

Un rapport en **texte lisible** — jamais un dump de JSON (règle projet). Y faire figurer, sans
qu'on ait à le demander :

- le tableau des temps, avec le temps absolu Lua comme référence et les coefficients ;
- les trois comptes d'instructions ;
- **la limite de validité** : ces chiffres ne valent que pour cette machine et ce moment, et ne se
  comparent ni à une autre machine ni à une autre session.

Puis `bash tests/run.sh`, commit, push (`main` et la branche de session).

## Ce qui est PROSCRIT dans le rapport

- Inventer une raison à un écart. S'en tenir aux faits mesurés.
- Attribuer un écart de quelques pour cent à un changement de code sans l'avoir mesuré : la
  disposition du code fait ±7 % sur `fib` (fait vérifié, cf. `CLAUDE.md`). Instructions stables et
  temps qui bouge ⇒ placement, il n'y a rien à optimiser.
- Comparer à des chiffres d'une autre session ou d'une autre machine, même « pour donner une
  idée ».
- Présenter une dérive mesurée sur des commits qui ne touchent pas le moteur : les bons jalons
  sortent de `git log -- src/vm.cpp src/value.h src/compiler.cpp src/opcode.h src/vm.h
  src/collections/`. Le conteneur part d'un clone superficiel, donc `git fetch --unshallow origin`
  avant toute mesure d'histoire.
