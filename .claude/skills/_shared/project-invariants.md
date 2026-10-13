# Invariants du projet (liste partagée par les revues)

Utilisée par `/code-review`, dans ses deux modes (les fichiers que le diff touche, ou le module relu). Ce sont
des pièges que CLAUDE.md documente et qu'une relecture isolée ne devine pas : chacun a déjà coûté un
bug réel. Une entrée ne se signale que si le code relu la viole VRAIMENT — pas parce qu'elle figure
ici. Quand CLAUDE.md change, c'est cette liste qu'on met à jour, pas deux copies.

## Moteur C++ (`src/`)

- un handler *computed-goto* qui laisse une variable à destructeur non trivial en portée au `NEXT()` ;
- un `release()` de pool qui teste la capacité **avant** le `clear()` (ré-entrance : `n` change
  pendant le clear) ;
- une identité d'objet gardée à travers un appel Ollin (pointeur ou référence dans un vecteur qui
  peut `push_back`) au lieu d'un couple `{slot, gen}` ;
- du code Ollin appelé depuis le rappel audio ;
- un nom exposé à l'API en `snake_case`, ou un identifiant C++ interne en camelCase (ce que
  `tests/check_naming.sh` vérifie déjà — ne pas le répéter s'il passe) ;
- un nouveau type ref-compté placé avant le pivot `T_STRING`, ou un constructeur `Value(bool)` ;
- `fn_stack_` ou toute pile dont des références vivent à travers un empilement : un `std::deque`,
  jamais un `std::vector` ;
- une enveloppe nommée, un argument par défaut ou un opcode ajouté sur le chemin chaud de la VM
  (`push_frame`, `run_goto`) : le coût est structurel et se MESURE (`bash bench/icount.sh`) ;
- un tween qui arrondit, ou qui écrit une borne autrement que par `write_bound`.

## Web app (`docs/`)

- un `init(ctx)` de vue dont le `cleanup()` ne retire pas un écouteur global (window/document) ni ne
  met la boucle en pause ;
- une vue qui réécrit un état global de la page (manifeste, titre, icône) sans que rien ne le défasse
  si elle est supersédée pendant son démarrage ;
- un test de nom de vue (`'run'`, `'play'`) en dur au lieu d'un drapeau de `ROUTES` ;
- une reprise de boucle sans `resumeLoop` : sans coupure d'horloge, la première image compte toute la
  pause et chaque animation saute ;
- une règle de chemin recopiée au lieu de partager `resolveImport` / `pathNormalise` avec `src/paths.h`.

## Code Ollin (`.ol`, `docs/samples/`)

- `0` est FAUX : un identifiant, un indice ou un compte qui peut valoir 0 se compare à `nil`
  explicitement, jamais par véracité ;
- un champ animé par `tween` est un FLOTTANT entre ses bornes : le code qui s'en sert d'indice ou de
  compte sans l'arrondir (`math.round`) échoue au milieu de l'animation, jamais aux bornes — d'où un
  bug qu'un test aux extrémités ne voit pas ;
- un son demandé dans `setup()` : le navigateur ne sonne qu'après un premier geste ;
- un callback d'entrée (`mouse.pressed`…) déclaré deux fois : le dernier écrase l'autre en silence.
