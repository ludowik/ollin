#pragma once

#include <string>

// In-memory registry of .ol sources, keyed by path. On WASM it lets `import "utils.ol"`
// resolve against files provided by the host (the playground) instead of a real filesystem;
// on a native build it stays empty and the parser falls back to reading from disk.
void source_preload(const std::string& path, const std::string& content);
void source_reset();
bool source_get(const std::string& path, std::string& out);
