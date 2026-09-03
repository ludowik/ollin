#include "source_registry.h"

#include <unordered_map>

static std::unordered_map<std::string, std::string> s_sources;

void source_preload(const std::string& path, const std::string& content) {
    s_sources[path] = content;
}

void source_reset() {
    s_sources.clear();
}

bool source_get(const std::string& path, std::string& out) {
    auto it = s_sources.find(path);
    if (it == s_sources.end())
        return false;
    out = it->second;
    return true;
}

static std::string s_program_dir;

void program_dir_set(const std::string& dir) {
    s_program_dir = dir;
}

const std::string& program_dir() {
    return s_program_dir;
}
