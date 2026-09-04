#pragma once

#include <string>
#include <vector>

// PATHS: the one place the engine decides what a written path means. The rules are shared by the
// import statement (a module's identity), the two entry points (the program's own directory) and
// the resource loaders (a model, an image), and each of them having written its own version is how
// they came to disagree — an entry kept in a sub-directory once looked for its siblings at the
// root, and a resource path was never normalised while an import always was.

// Everything up to the last separator, empty when there is none.
std::string path_dir(const std::string& file);

// "." and ".." collapsed. The result is a path's IDENTITY: the source-registry key, the import
// deduplication key, and the name a forked web project stores a file under, so "a/../lib/x.ol" and
// "lib/x.ol" must come out as ONE string. A ".." that cannot be collapsed is kept: it may still
// mean something on a filesystem.
std::string path_normalise(const std::string& p);

// Is the path anchored, hence not to be resolved against anything? A leading "/" or a Windows
// drive letter.
bool path_is_absolute(const std::string& p);

// base + path, unless the path is absolute, then normalised.
std::string path_resolve(const std::string& base, const std::string& path);

// The PROGRAM's own directory, set once from the entry file's name. A resource a script names is
// looked for there first: an example kept in its own directory carries its data beside it, and it
// no longer matters which directory the process was started from.
void program_dir_set(const std::string& dir);
const std::string& program_dir();

// Where to look for a resource NAMED by a script, in order: beside the program, then the name as
// written. One list, so every loader searches the same places — a loader is left with nothing to
// decide but "did it load?".
std::vector<std::string> asset_candidates(const std::string& name);
