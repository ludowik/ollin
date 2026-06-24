#pragma once
#include "chunk.h"
#include <string>
#include <vector>
#include <cstdint>

Value makeImageModule();

// WASM interop: preload raw bytes under a name so image.load(name) works
void image_preload(const std::string& name,
                   const std::vector<uint8_t>& bytes,
                   const std::string& ext);   // ext with dot, e.g. ".png"

// Convenience: decode base64 then preload. ext without dot, e.g. "png".
void image_preload_b64(const std::string& name,
                       const std::string& b64,
                       const std::string& ext);

// Called at the start of each ollin_run() to release stale GL handles
void image_reset();
