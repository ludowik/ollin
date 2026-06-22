cmake_minimum_required(VERSION 3.16)
project(ollin VERSION 0.1 LANGUAGES CXX)

set(CMAKE_SUPPRESS_DEVELOPER_WARNINGS 1 CACHE INTERNAL "")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(MSVC)
    message(FATAL_ERROR "MSVC is not supported: the VM uses computed-goto (GNU extension), which requires GCC or Clang.")
endif()

set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_GAMES    OFF CACHE BOOL "" FORCE)

set(OLLIN_SOURCES
    src/chunk.cpp
    src/array.cpp
    src/map.cpp
    src/lexer.cpp
    src/parser.cpp
    src/compiler.cpp
    src/vm.cpp
    src/modules.cpp
    src/core_module.cpp
    src/color_module.cpp
    src/math_module.cpp
    src/string_module.cpp
)

if(EMSCRIPTEN)
    set(PLATFORM "Web"                     CACHE STRING "" FORCE)
    set(GRAPHICS "GRAPHICS_API_OPENGL_ES3" CACHE STRING "" FORCE)

    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/raylib/CMakeLists.txt")
        add_subdirectory(third_party/raylib)
    else()
        include(FetchContent)
        FetchContent_Declare(raylib
            GIT_REPOSITORY https://github.com/raysan5/raylib.git
            GIT_TAG        6.0
            GIT_SHALLOW    TRUE
        )
        FetchContent_MakeAvailable(raylib)
    endif()

    add_executable(ollin_wasm src/wasm_main.cpp ${OLLIN_SOURCES} src/raylib_module.cpp)
    target_include_directories(ollin_wasm PRIVATE src)
    target_compile_options(ollin_wasm PRIVATE -Wall -Wextra -fexceptions)
    set_target_properties(ollin_wasm PROPERTIES OUTPUT_NAME "ollin" SUFFIX ".js")
    target_link_libraries(ollin_wasm PRIVATE raylib)
    target_link_options(ollin_wasm PRIVATE
        -sMODULARIZE=1
        -sEXPORT_NAME=OllinModule
        -sALLOW_MEMORY_GROWTH=1
        -sNO_EXIT_RUNTIME=1
        -sDISABLE_EXCEPTION_CATCHING=0
        -sUSE_GLFW=3
        -sMAX_WEBGL_VERSION=2
        -sMIN_WEBGL_VERSION=2
        --bind
    )
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        target_link_options(ollin_wasm PRIVATE -sASSERTIONS=1)
    endif()
    add_custom_command(TARGET ollin_wasm POST_BUILD
        COMMAND python3 ${CMAKE_CURRENT_SOURCE_DIR}/scripts/update_build_date.py
        COMMENT "Updating build date in docs/index.html"
    )
else()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/raylib/CMakeLists.txt")
        add_subdirectory(third_party/raylib)
        set(OLLIN_GRAPHICS_SOURCE src/raylib_module.cpp)
        set(OLLIN_GRAPHICS_LIB raylib)
    else()
        message(STATUS "raylib not found — building with graphics stub (no window)")
        set(OLLIN_GRAPHICS_SOURCE src/graphics_stub.cpp)
        set(OLLIN_GRAPHICS_LIB "")
    endif()

    add_executable(ollin src/main.cpp ${OLLIN_SOURCES} ${OLLIN_GRAPHICS_SOURCE})
    target_include_directories(ollin PRIVATE src)
    target_link_libraries(ollin PRIVATE ${OLLIN_GRAPHICS_LIB})
    target_compile_options(ollin PRIVATE -Wall -Wextra)
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        set_source_files_properties(src/vm.cpp PROPERTIES COMPILE_OPTIONS "-Og")
    endif()
endif()
