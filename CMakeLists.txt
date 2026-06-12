cmake_minimum_required(VERSION 3.16)
project(tau VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(ollin
    src/main.cpp
    src/chunk.cpp
    src/lexer.cpp
    src/parser.cpp
    src/compiler.cpp
    src/vm.cpp
)

target_include_directories(ollin PRIVATE src)

if(MSVC)
    target_compile_options(ollin PRIVATE /W4)
else()
    target_compile_options(ollin PRIVATE -Wall -Wextra)
    # -Og uniquement sur vm.cpp : boucle d'exécution rapide sans casser
    # les breakpoints des autres modules (compiler, parser, lexer…)
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        set_source_files_properties(src/vm.cpp PROPERTIES COMPILE_OPTIONS "-Og")
    endif()
endif()
