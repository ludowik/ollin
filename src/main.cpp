#include "compiler.h"
#include "lexer.h"
#include "modules/data_module.h"
#include "parser.h"
#include "vm.h"
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_set>

static Program parseFile(const std::string& path) {
    std::ifstream f(path);
    if (!f)
        return {};
    std::ostringstream ss;
    ss << f.rdbuf();
    return Parser(Lexer(ss.str()).tokenize()).parse();
}

static void appendProgram(Program& dst, Program src) {
    for (auto& s : src.stmts)
        dst.stmts.push_back(std::move(s));
}

int main(int argc, char* argv[]) {
    std::string scriptPath = (argc < 2) ? "main.ol" : argv[1];
    auto sep = scriptPath.find_last_of("/\\");
    std::string dir = (sep != std::string::npos) ? scriptPath.substr(0, sep + 1) : "";

    // Persistance `data` : sidecar « <script>.data.json » (projet) + fichier home (global).
    {
        const char* home = std::getenv("HOME");
        std::string global = (home ? std::string(home) + "/" : "") + ".ollin-data-global.json";
        dataSetNativePaths(scriptPath + ".data.json", global);
    }

    try {
        auto imported = std::make_shared<std::unordered_set<std::string>>();
        Program program;
        appendProgram(program, parseFile(dir + "config.ol"));

        std::ifstream main_file(scriptPath);
        if (!main_file) {
            std::cerr << "cannot open: " << scriptPath << '\n';
            return 1;
        }
        std::ostringstream ss;
        ss << main_file.rdbuf();
        appendProgram(program, Parser(Lexer(ss.str()).tokenize(), dir, imported).parse());

        VM vm;
        vm.execute(Compiler().compile(program));
        vm.runEntryHooks(); // setup() puis draw()→graphics.run (logique partagée natif/WASM)
    } catch (const std::exception& e) {
        std::cerr << scriptPath << ": " << e.what() << '\n';
        return 1;
    }
    return 0;
}
