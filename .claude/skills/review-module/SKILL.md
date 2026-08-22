---
name: review-module
description: Revue COMPLÈTE d'un module — lit tout le code du module, pas un diff, et ignore refs/reviewed. Prend en argument un chemin (src/modules/ui_module.cpp), un dossier (src/collections/) ou un nom court (ui, tween, sound). À utiliser quand la question porte sur l'état d'un module, pas sur ce qui vient d'être modifié.
---

`effort moyen → lecture INTÉGRALE du module → findings classés → corrections`

Cette revue **ne regarde aucun diff**. Elle ne consulte pas `refs/reviewed` et ne
l'avance pas : elle juge le module tel qu'il est aujourd'hui, que le code date du
dernier commit ou d'il y a six mois.

## Turn 1 — établir le périmètre

L'argument désigne le module. Le résoudre ainsi :
- un chemin de fichier → ce fichier ;
- un dossier → tous ses fichiers ;
- un nom court (`ui`, `tween`, `sound`, `graphics`, `touch`, `image`, `data`…) →
  `src/modules/<nom>_module.cpp` **plus** tout fichier frère du même préfixe :
  en-tête (`<nom>_module.h`), stub (`<nom>_stub.cpp`), frontière interne
  (`<nom>_internal.h`), fichiers éclatés (`graphics3d.cpp`, `graphics_quat.cpp`,
  `sound_output*.cpp`). Un module se juge avec sa frontière, pas sans.

Lire ces fichiers **en entier**. Puis, en un seul appel de recherche, relever les
**appelants** hors du module (`grep` du nom des fonctions exposées et des
symboles de la frontière) : beaucoup de défauts d'un module natif ne sont visibles
que du côté de son appelant — un `reset` jamais appelé, un rappel invoqué au
mauvais moment de la frame, un handle gardé à travers un appel Ollin.

## Turn 2 — ce qu'on cherche

Dans cet ordre de gravité :

1. **Correctness** : condition fausse, off-by-one, test de véracité sur une valeur
   qui peut valoir 0, garde absente, erreur avalée, valeur non initialisée,
   débordement d'un tableau de taille fixe.
2. **Invariants du projet**, ceux que CLAUDE.md documente et qu'une relecture
   isolée ne devine pas :
   - un handler *computed-goto* qui laisse une variable à destructeur non trivial
     en portée au `NEXT()` ;
   - un `release()` de pool qui teste la capacité **avant** le `clear()`
     (ré-entrance : `n` change pendant le clear) ;
   - une identité d'objet gardée à travers un appel Ollin (pointeur ou référence
     dans un vecteur qui peut `push_back`) au lieu d'un couple `{slot, gen}` ;
   - du code Ollin appelé depuis le rappel audio ;
   - un nom exposé à l'API en `snake_case`, ou un identifiant C++ interne en
     camelCase (ce que `tests/check_naming.sh` vérifie déjà — ne pas le répéter
     s'il passe) ;
   - un nouveau type ref-compté placé avant le pivot `T_STRING`.
3. **Duplication** : deux chemins qui font la même chose alors que le module
   porte déjà le helper, ou une validation recopiée entre le module et son stub
   au lieu de vivre dans l'en-tête partagé.
4. **Code mort** : fonction, champ ou branche que plus aucun appelant n'atteint.

Ne PAS signaler le style, le nommage local, la performance supposée sans mesure,
ni les tests manquants — sauf un cas non couvert qui EXPLIQUE un finding.

Sortir les findings du plus grave au moins grave, une ligne chacun :
`chemin/fichier.ext:123 — ce qui ne va pas et l'échec concret`. Pas de plafond de
nombre, mais rien de spéculatif : un finding sans échec concret n'est pas un
finding. Si le module est sain, sortir exactement `(none)` — et le dire sans
chercher à remplir. Réponse **en français**.

## Turn 3 — CORRIGER, sans demander

Comme pour `/code-review` : appliquer chaque finding dans le même tour,
recompiler, lancer `bash tests/run.sh`, committer, pousser. Un défaut de
comportement corrigé se **fige dans un test** (`tests/regressions.ol` pour la
sémantique, `tests/test_errors.sh` pour un refus) : c'est ce qui distingue une
revue d'une opinion. Ne jamais demander l'autorisation de corriger.

Exception, à énoncer en une ligne : un finding dont la correction changerait un
comportement voulu, ou demanderait de réécrire le module.

## Ce que cette revue ne fait pas

Elle ne remplace pas `/code-review` (le diff en cours, bas effort) ni `/simplify`
(la qualité du code modifié). Et elle **n'avance jamais** `refs/reviewed` : les
commits non encore revus par `/code-review` restent en attente.
