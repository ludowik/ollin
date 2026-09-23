# Résolution de la cible d'une revue (algorithme partagé)

Utilisé par `/code-review` (repère `refs/reviewed`) et `/simplify` (repère
`refs/simplified`) — deux passes indépendantes sur le même diff (correctness pour
l'une, qualité pour l'autre), chacune avec SON PROPRE repère : les confondre ferait
avancer l'une sans que l'autre ait jamais eu lieu.

Le repère est un ref git LOCAL, propre au conteneur : une nouvelle session repart
d'un clone frais sans lui (repli sur le dernier commit, puis le mécanisme se
ré-amorce).

Résoudre la cible dans cet ordre, s'arrêter à la première non vide :
1. argument explicite passé à la commande, s'il y en a un ;
2. `git diff HEAD` (modifications non commitées) — la revue précède souvent le commit ;
3. si le repère existe (`git rev-parse --verify --quiet <repère>`) :
   `git diff <repère>..HEAD` — TOUS les commits depuis la dernière passe, quel
   qu'en soit le nombre. C'est le cas NORMAL : la règle projet impose de committer
   et pousser sur `main` après chaque feature, et une reprise de session réaligne
   `@{upstream}` sur `origin/main` → sans repère on ne verrait que le dernier
   commit, alors qu'un commit intercalé (ex. un rebuild WASM) ne doit rien masquer ;
4. sinon `git diff @{upstream}...HEAD` (ou `main...HEAD` sans upstream) ;
5. sinon `git diff HEAD~1..HEAD` — dernier commit (première passe du conteneur :
   le repère n'existe pas encore). Ne jamais conclure « rien à revoir » sans avoir
   essayé ce dernier recours.

## Après la revue — avancer le repère

Si la cible retenue était un intervalle commité (cas 3, 4 ou 5), poser le repère
sur l'état revu : `git update-ref <repère> HEAD`. Ainsi la prochaine passe repart
de là. Ne PAS l'avancer pour un argument explicite (cas 1) ni des modifications
non commitées (cas 2) — les éléments non encore passés en revue doivent rester en
attente. À faire même si le verdict est `(none)` ou qu'aucun constat n'a été
retenu (l'état a bien été revu).
