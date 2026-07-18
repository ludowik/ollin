#pragma once
#include "value.h"
#include <string>

// Module `data` : persistance clé→valeur par PROJET (isolée) et GLOBALE (partagée).
// Valeurs scalaires (nombre / chaîne / booléen). Persistance write-through :
//   WASM  → localStorage (via window.__ollinData, fourni par la SPA)
//   natif → fichier JSON « sidecar »
Value makeDataModule();

// Charge les données au début d'un run (blobs JSON de chaque portée).
// WASM : appelé par l'hôte JS (embind « dataLoad ») avant execute.
void dataLoad(const std::string& projectBlob, const std::string& globalBlob);

#ifndef __EMSCRIPTEN__
// Natif : fixe les fichiers sidecar (projet = à côté du script, global = home) et
// charge leur contenu. Les écritures (set/delete/clear) réécrivent ces fichiers.
void dataSetNativePaths(const std::string& projectFile, const std::string& globalFile);
#endif
