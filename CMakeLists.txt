cmake_minimum_required(VERSION 3.16)
project(tau VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(tau
    src/main.cpp
    src/chunk.cpp
    src/lexer.cpp
    src/parser.cpp
    src/compiler.cpp
    src/vm.cpp
)

target_include_directories(tau PRIVATE src)

if(MSVC)
    target_compile_options(tau PRIVATE /W4)
else()
    target_compile_options(tau PRIVATE -Wall -Wextra)
    # -Og : optimise pour le debug (inlining basique, breakpoints intacts)
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        target_compile_options(tau PRIVATE -Og)
    endif()
endif()
