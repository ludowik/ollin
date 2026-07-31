#pragma once
#include "value.h"
#include <string>

// Module `data` : persistance clé→valeur par PROJET (isolée) et GLOBALE (partagée).
// Valeurs scalaires (nombre / chaîne / booléen). Persistance write-through :
//   WASM  → localStorage (via window.__ollinData, fourni par la SPA)
//   natif → fichier JSON « sidecar »
Value make_data_module();

// Charge les données au début d'un run (blobs JSON de chaque portée).
// WASM : appelé par l'hôte JS (embind « dataLoad ») avant execute.
void data_load(const std::string& project_blob, const std::string& global_blob);

#ifndef __EMSCRIPTEN__
// Natif : fixe les fichiers sidecar (projet = à côté du script, global = home) et
// charge leur contenu. Les écritures (set/delete/clear) réécrivent ces fichiers.
void data_set_native_paths(const std::string& project_file, const std::string& global_file);
#endif
