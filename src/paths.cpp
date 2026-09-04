#include "paths.h"

#include <sstream>

std::string path_dir(const std::string& file) {
    auto sep = file.find_last_of("/\\");
    return (sep != std::string::npos) ? file.substr(0, sep + 1) : "";
}

std::string path_normalise(const std::string& p) {
    bool absolute = !p.empty() && p[0] == '/';
    std::vector<std::string> parts;
    std::istringstream segments(p);
    std::string seg;
    while (std::getline(segments, seg, '/')) {
        if (seg == "..") {
            if (!parts.empty() && parts.back() != "..")
                parts.pop_back();
            else if (!absolute)
                parts.push_back(seg);
        } else if (!seg.empty() && seg != ".") {
            parts.push_back(seg);
        }
    }
    std::string out = absolute ? "/" : "";
    for (size_t k = 0; k < parts.size(); k++) {
        if (k)
            out += "/";
        out += parts[k];
    }
    return out;
}

bool path_is_absolute(const std::string& p) {
    return !p.empty() && (p[0] == '/' || (p.size() > 1 && p[1] == ':'));
}

std::string path_resolve(const std::string& base, const std::string& path) {
    return path_normalise(path_is_absolute(path) ? path : base + path);
}

static std::string s_program_dir;

void program_dir_set(const std::string& dir) {
    s_program_dir = dir;
}

const std::string& program_dir() {
    return s_program_dir;
}

std::vector<std::string> asset_candidates(const std::string& name) {
    // An anchored name says where it lives: resolving it against anything would be a guess.
    if (path_is_absolute(name))
        return {name};
    std::vector<std::string> out;
    if (!s_program_dir.empty())
        out.push_back(path_resolve(s_program_dir, name));
    out.push_back(name);
    return out;
}
