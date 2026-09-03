#pragma once

#include <string>

// In-memory registry of .ol sources, keyed by path. On WASM it lets `import "utils.ol"`
// resolve against files provided by the host (the playground) instead of a real filesystem;
// on a native build it stays empty and the parser falls back to reading from disk.
void source_preload(const std::string& path, const std::string& content);
void source_reset();
bool source_get(const std::string& path, std::string& out);

// The PROGRAM's own directory, set once from the entry file's name (path_dir). A resource named by
// a script — a 3D model, an image — is looked for THERE first, exactly as an import resolves
// against the importing file's directory: an example kept in its own directory carries its data
// beside it, and it no longer matters which directory the process was started from.
// Empty when the program has no path of its own (the playground's unsaved draft).
void program_dir_set(const std::string& dir);
const std::string& program_dir();
