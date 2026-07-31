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
#include <vector>

static void append_program(Program& dst, Program src) {
    for (auto& s : src.stmts)
        dst.stmts.push_back(std::move(s));
    // source_files entries from src are already in the shared table — no merge needed
}

int main(int argc, char* argv[]) {
    std::string script_path = (argc < 2) ? "main.ol" : argv[1];
    auto sep = script_path.find_last_of("/\\");
    std::string dir = (sep != std::string::npos) ? script_path.substr(0, sep + 1) : "";

    // Persistance `data` : sidecar « <script>.data.json » (projet) + fichier home (global).
    {
        const char* home = std::getenv("HOME");
        std::string global = (home ? std::string(home) + "/" : "") + ".ollin-data-global.json";
        data_set_native_paths(script_path + ".data.json", global);
    }

    try {
        auto imported = std::make_shared<std::unordered_set<std::string>>();
        auto source_files = std::make_shared<std::vector<std::string>>();
        Program program;

        // config.ol optionnel — file_idx 0 si présent
        {
            std::string cfg_path = dir + "config.ol";
            std::ifstream f(cfg_path);
            if (f) {
                std::ostringstream ss;
                ss << f.rdbuf();
                int fi = (int)source_files->size();
                source_files->push_back(cfg_path);
                append_program(program, Parser(Lexer(ss.str(), cfg_path, fi).tokenize(),
                                             dir, imported, nullptr, source_files).parse());
            }
        }

        std::ifstream main_file(script_path);
        if (!main_file) {
            std::cerr << "cannot open: " << script_path << '\n';
            return 1;
        }
        std::ostringstream ss;
        ss << main_file.rdbuf();
        int fi = (int)source_files->size();
        source_files->push_back(script_path);
        append_program(program, Parser(Lexer(ss.str(), script_path, fi).tokenize(),
                                     dir, imported, nullptr, source_files).parse());
        // Après parse() le program.source_files = *source_files (snapshot) ; le
        // compilateur utilise chunk.source_files copié depuis program.source_files.
        program.source_files = *source_files;

        VM vm;
        vm.execute(Compiler().compile(program));
        vm.run_entry_hooks(); // setup() puis draw()→graphics.run (logique partagée natif/WASM)
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n'; // filename:line déjà dans le message
        return 1;
    }
    return 0;
}
