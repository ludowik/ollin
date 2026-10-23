// UNIT test of the two engine units no script can reach on its own: the path rules (the entry points and
// the resource loaders call them with the program's directory, which a headless test never sets) and the
// in-memory source registry (filled by the playground, empty on a native run). Plain asserts, no framework:
// the build target is `unit_tests`, run by tests/check_unit.sh.
#include "paths.h"
#include "source_registry.h"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

static int s_failures = 0;

static void expect(bool ok, const char* what) {
    if (ok)
        return;
    std::printf("FAIL %s\n", what);
    s_failures++;
}

static void expect_eq(const std::string& got, const std::string& want, const char* what) {
    if (got == want)
        return;
    std::printf("FAIL %s: got '%s', wanted '%s'\n", what, got.c_str(), want.c_str());
    s_failures++;
}

static void test_dir() {
    expect_eq(path_dir("a/b/c.ol"), "a/b/", "path_dir keeps the trailing separator");
    expect_eq(path_dir("c.ol"), "", "path_dir of a bare name is empty");
    expect_eq(path_dir("a\\b.ol"), "a\\", "path_dir knows the Windows separator");
    expect_eq(path_dir(""), "", "path_dir of nothing");
}

static void test_normalise() {
    expect_eq(path_normalise("a/../lib/x.ol"), "lib/x.ol", "a '..' cancels the segment before it");
    expect_eq(path_normalise("./a//b/."), "a/b", "'.' and empty segments vanish");
    expect_eq(path_normalise("../x"), "../x", "a leading '..' cannot be collapsed and is kept");
    expect_eq(path_normalise("a/../../x"), "../x", "a '..' beyond the start is kept");
    expect_eq(path_normalise("../../a"), "../../a", "two kept '..' stay in order");
    expect_eq(path_normalise("/a/../../x"), "/x", "a '..' above the root is dropped");
    expect_eq(path_normalise("a/b/../.."), "", "a path that cancels out is empty");
    expect_eq(path_normalise("/"), "/", "the root stays the root");
    expect_eq(path_normalise(".."), "..", "a lone '..'");
    expect_eq(path_normalise(""), "", "nothing stays nothing");
}

static void test_absolute_and_resolve() {
    expect(path_is_absolute("/x"), "a leading slash is anchored");
    expect(path_is_absolute("C:\\x"), "a drive letter is anchored");
    expect(!path_is_absolute("x"), "a bare name is not");
    expect(!path_is_absolute(""), "an empty path is not");
    expect_eq(path_resolve("d/", "x.ol"), "d/x.ol", "a relative path is resolved against the base");
    expect_eq(path_resolve("d/", "/abs/x.ol"), "/abs/x.ol", "an absolute path ignores the base");
    expect_eq(path_resolve("a/b/", "../c.ol"), "a/c.ol", "the result is normalised");
}

static void test_assets() {
    expect_eq(program_dir(), "", "no program directory until one is set");
    expect(asset_candidates("m.glb") == std::vector<std::string>{"m.glb"}, "without a program directory: the name alone");
    program_dir_set("ex/");
    expect_eq(program_dir(), "ex/", "program_dir returns what was set");
    expect(asset_candidates("m.glb") == (std::vector<std::string>{"ex/m.glb", "m.glb"}),
           "beside the program first, then the name as written");
    expect(asset_candidates("/abs/m.glb") == std::vector<std::string>{"/abs/m.glb"},
           "an anchored name has one candidate, itself");
    expect(asset_candidates("../shared/m.glb") == (std::vector<std::string>{"shared/m.glb", "../shared/m.glb"}),
           "the beside-the-program candidate is normalised");
    program_dir_set("");
}

static void test_sources() {
    std::string out = "untouched";
    expect(!source_get("lib/x.ol", out), "an unknown source is not found");
    expect_eq(out, "untouched", "a miss leaves the output alone");
    source_preload("lib/x.ol", "var a = 1");
    expect(source_get("lib/x.ol", out), "a preloaded source is found");
    expect_eq(out, "var a = 1", "and it is what was preloaded");
    source_preload("lib/x.ol", "var a = 2");
    source_get("lib/x.ol", out);
    expect_eq(out, "var a = 2", "preloading again replaces the content");
    source_reset();
    expect(!source_get("lib/x.ol", out), "a reset forgets everything");
}

int main() {
    test_dir();
    test_normalise();
    test_absolute_and_resolve();
    test_assets();
    test_sources();
    if (s_failures) {
        std::printf("%d unit check(s) failed\n", s_failures);
        return 1;
    }
    std::printf("unit checks ok\n");
    return 0;
}
