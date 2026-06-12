# Tau — Scripting Language

## Stack
- Implémentation : **C++17**
- Build : **CMake** (cross-platform)
- Cibles : Windows, Linux, macOS, iOS, Android, wasm
- Runtime : **bytecode custom + VM stack-based**

## Architecture (pipeline strict, modules indépendants)

```
source .tau
  → Lexer     → std::vector<Token>          (token.h)
  → Parser    → Program (AST)               (ast.h)
  → Compiler  → Chunk (bytecode)            (chunk.h)
  → VM        → exécution
```

Chaque module ne connaît que les types qu'il consomme/produit.  
Les types partagés (`token.h`, `ast.h`, `chunk.h`) n'ont aucune dépendance entre eux.

## Structure des fichiers

```
tau/
├── CLAUDE.md
├── CMakeLists.txt
└── src/
    ├── token.h        types Token (partagé Lexer → Parser)
    ├── ast.h          nœuds AST  (partagé Parser → Compiler)
    ├── chunk.h/.cpp   bytecode   (partagé Compiler → VM)
    ├── lexer.h/.cpp
    ├── parser.h/.cpp
    ├── compiler.h/.cpp
    ├── vm.h/.cpp
    └── main.cpp       pipeline : Lexer | Parser | Compiler | VM
```

## Syntaxe

| Fichier | Propriétaire | Rôle |
|---|---|---|
| `syntax.tau` | utilisateur | source de vérité — déclare la syntaxe par l'exemple |
| `grammar.ebnf` | Claude | grammaire formelle dérivée de `syntax.tau` — à maintenir à chaque évolution |
| `test.tau` | Claude | fichier de tests libres — modifiable à volonté |
| `tau-vscode/` | Claude | extension VS Code (colorisation) — à maintenir à chaque évolution du langage |

## Versionning

- **Git** initialisé à la racine — utiliser `git restore <fichier>` pour annuler une modification
- Committer après chaque changement significatif

## Maintenance de CLAUDE.md

Mettre à jour ce fichier dès qu'un point important doit être mémorisé :
architecture, conventions, décisions, règles d'outillage.  
Ne pas documenter ce qui n'est pas encore implémenté.

## Opcodes VM

| Opcode      | Opérandes       | Description                        |
|-------------|-----------------|-------------------------------------|
| LOAD_CONST  | idx (uint16)    | push constants[idx]                |
| LOAD_VAR    | idx (uint16)    | push vars[identifiers[idx]]        |
| STORE_VAR   | idx (uint16)    | pop → vars[identifiers[idx]]       |
| ADD/SUB/MUL/DIV |             | pop 2, push résultat               |
| GT / LT     |                 | pop 2, push 1.0 si vrai sinon 0.0  |
| JUMP        | addr (uint16)   | saut inconditionnel                |
| JUMP_IF_FALSE | addr (uint16) | pop cond ; saute si 0.0            |
| CALL        | idx, argc (u8)  | appel builtin identifiers[idx]     |
| HALT        |                 | arrêt                              |
