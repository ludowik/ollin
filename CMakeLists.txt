cmake_minimum_required(VERSION 3.16)
project(ollin VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(OLLIN_SOURCES
    src/chunk.cpp
    src/array.cpp
    src/map.cpp
    src/lexer.cpp
    src/parser.cpp
    src/compiler.cpp
    src/vm.cpp
    src/stdlib.cpp
    src/math_module.cpp
)

if(EMSCRIPTEN)
    add_executable(ollin_wasm src/wasm_main.cpp ${OLLIN_SOURCES})
    target_include_directories(ollin_wasm PRIVATE src)
    target_compile_options(ollin_wasm PRIVATE -Wall -Wextra -fexceptions)
    set_target_properties(ollin_wasm PROPERTIES OUTPUT_NAME "ollin" SUFFIX ".js")
    target_link_options(ollin_wasm PRIVATE
        -sMODULARIZE=1
        -sEXPORT_NAME=OllinModule
        -sALLOW_MEMORY_GROWTH=1
        -sNO_EXIT_RUNTIME=1
        -sDISABLE_EXCEPTION_CATCHING=0
        --bind
    )
else()
    add_executable(ollin src/main.cpp ${OLLIN_SOURCES})
    target_include_directories(ollin PRIVATE src)
    if(MSVC)
        target_compile_options(ollin PRIVATE /W4)
    else()
        target_compile_options(ollin PRIVATE -Wall -Wextra)
        if(CMAKE_BUILD_TYPE STREQUAL "Debug")
            set_source_files_properties(src/vm.cpp PROPERTIES COMPILE_OPTIONS "-Og")
        endif()
    endif()
endif()
