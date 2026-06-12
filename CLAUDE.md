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

## Syntaxe couverte (syntax.tau)

```
var a = 12.12
var b, c = 1, 2      % déclaration multiple
var res = a + b
print(res)           % builtin
```

Opérateurs : `+` `-` `*` `/`  
Types : `double` (tout est double pour l'instant)  
Commentaires : `%` (une ligne) — **pas encore implémenté**

## Opcodes VM

| Opcode      | Opérandes       | Description                        |
|-------------|-----------------|-------------------------------------|
| LOAD_CONST  | idx (uint16)    | push constants[idx]                |
| LOAD_VAR    | idx (uint16)    | push vars[identifiers[idx]]        |
| STORE_VAR   | idx (uint16)    | pop → vars[identifiers[idx]]       |
| ADD/SUB/MUL/DIV |             | pop 2, push résultat               |
| CALL        | idx, argc (u8)  | appel builtin identifiers[idx]     |
| HALT        |                 | arrêt                              |
