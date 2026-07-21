#pragma once
#include <cstdint>
#include <string>
#include <vector>

struct SourceLoc {
    uint16_t file_idx = 0;
    uint16_t line = 0;

    std::string str(const std::vector<std::string>& files) const {
        const std::string& f = file_idx < files.size() ? files[file_idx] : "?";
        return f + ":" + std::to_string(line);
    }
};
