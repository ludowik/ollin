#pragma once

#include <string>

// Registre de fichiers source .ol en mémoire, indexés par leur chemin
// (relatif au projet ou résolu). Utilisé sur WASM pour que `import "utils.ol"`
// se résolve contre des fichiers fournis par l'hôte (le playground) plutôt que
// par un vrai système de fichiers. Sur un build natif le registre reste vide et
// le parser retombe sur la lecture disque.
void source_preload(const std::string& path, const std::string& content);
void source_reset();
bool source_get(const std::string& path, std::string& out);
