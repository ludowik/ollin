#pragma once
#include "value.h"
#include <string>

// The `data` module: key-value persistence, PROJECT-scoped (isolated) and GLOBAL (shared).
// Scalar values only — number, string, boolean. Write-through persistence:
//   WASM  → localStorage (through window.__ollinData, supplied by the SPA)
//   native: a JSON sidecar file
Value make_data_module();

// Loads the data at the start of a run, one JSON blob per scope. On WASM the JS host calls it
// through embind ("dataLoad") before execute.
void data_load(const std::string& project_blob, const std::string& global_blob);

#ifndef __EMSCRIPTEN__
// Native: sets the sidecar files — project next to the script, global in the home directory —
// and loads their contents. Writes (set, delete, clear) rewrite those files.
void data_set_native_paths(const std::string& project_file, const std::string& global_file);
#endif
