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

# Build natif AVEC raylib (fenêtre/graphique) au lieu du stub. OFF par défaut :
# le build natif standard reste headless-safe (nécessaire pour les environnements
# distants sans accès réseau à raylib). Activer localement via -DOLLIN_NATIVE_RAYLIB=ON
# (cache CMake local à build/, non partagé) ou tools/native-gfx.sh (build-gfx/, tests Xvfb).
option(OLLIN_NATIVE_RAYLIB "Native build with raylib graphics (default: stub)" OFF)

set(OLLIN_SOURCES
    src/chunk.cpp
    src/collections/array.cpp
    src/collections/map.cpp
    src/lexer.cpp
    src/parser.cpp
    src/compiler.cpp
    src/vm.cpp
    src/source_registry.cpp
    src/modules/modules.cpp
    src/modules/core_module.cpp
    src/modules/color_module.cpp
    src/modules/math_module.cpp
    src/modules/string_module.cpp
    src/modules/data_module.cpp
)

if(EMSCRIPTEN)
    set(PLATFORM "Web"                     CACHE STRING "" FORCE)
    set(GRAPHICS "GRAPHICS_API_OPENGL_ES3" CACHE STRING "" FORCE)

    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/libs/raylib/CMakeLists.txt")
        add_subdirectory(libs/raylib)
    else()
        include(FetchContent)
        FetchContent_Declare(raylib
            GIT_REPOSITORY https://github.com/raysan5/raylib.git
            GIT_TAG        6.0
            GIT_SHALLOW    TRUE
        )
        FetchContent_MakeAvailable(raylib)
    endif()

    # raylib désactive le JPG par défaut (config.h : SUPPORT_FILEFORMAT_JPG 0).
    # On l'active pour que image.load accepte les .jpg/.jpeg — sans modifier la
    # source raylib : la valeur 1 l'emporte sur le #ifndef de config.h, ce qui
    # évite le #define STBI_NO_JPEG de rtextures.c.
    if(TARGET raylib)
        target_compile_definitions(raylib PRIVATE SUPPORT_FILEFORMAT_JPG=1)
    endif()

    add_executable(ollin_wasm src/wasm_main.cpp ${OLLIN_SOURCES} src/modules/graphics_module.cpp src/modules/graphics3d.cpp src/modules/graphics_quat.cpp src/modules/keyboard_module.cpp src/modules/mouse_module.cpp src/modules/window_module.cpp src/modules/image_module.cpp)
    target_include_directories(ollin_wasm PRIVATE src libs)
    target_compile_options(ollin_wasm PRIVATE -Wall -Wextra -fexceptions)
    set_target_properties(ollin_wasm PROPERTIES OUTPUT_NAME "ollin" SUFFIX ".js")
    target_link_libraries(ollin_wasm PRIVATE raylib)
    target_link_options(ollin_wasm PRIVATE
        -sMODULARIZE=1
        -sEXPORT_NAME=OllinModule
        # Mémoire FIXE (pas de croissance) — IMPÉRATIF pour iOS/WebKit. Depuis emsdk
        # 6.0.x, avec ALLOW_MEMORY_GROWTH la mémoire WASM est un ArrayBuffer
        # *redimensionnable* quand le navigateur le supporte. Or WebKit REFUSE une
        # vue typée basée sur un ArrayBuffer redimensionnable comme argument de
        # glTexImage2D → « srcData must be an instance of ArrayBufferView » à CHAQUE
        # upload de texture (tout script graphique plante sur iOS ; Chrome tolère →
        # bug iOS-only). Une mémoire fixe garantit un ArrayBuffer classique, dont les
        # vues sont acceptées. 128 Mo = large pour le playground (interpréteur +
        # raylib ~40 Mo + données utilisateur).
        -sALLOW_MEMORY_GROWTH=0
        -sINITIAL_MEMORY=134217728
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
    # Tampon de date optionnel : ne casse pas le build si le script est absent.
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tools/update_build_date.py")
        add_custom_command(TARGET ollin_wasm POST_BUILD
            COMMAND python3 ${CMAKE_CURRENT_SOURCE_DIR}/tools/update_build_date.py
            COMMENT "Updating build date in docs/index.html"
        )
    endif()
else()
    if(OLLIN_NATIVE_RAYLIB)
        # raylib via libs/raylib s'il existe, sinon FetchContent (qui réutilise le
        # cache si -DFETCHCONTENT_SOURCE_DIR_RAYLIB=<src> est passé — cf. native-gfx.sh).
        if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/libs/raylib/CMakeLists.txt")
            add_subdirectory(libs/raylib)
        else()
            include(FetchContent)
            FetchContent_Declare(raylib
                GIT_REPOSITORY https://github.com/raysan5/raylib.git
                GIT_TAG        6.0
                GIT_SHALLOW    TRUE
            )
            FetchContent_MakeAvailable(raylib)
        endif()
        # Active le décodage JPG/JPEG dans raylib (désactivé par défaut).
        if(TARGET raylib)
            target_compile_definitions(raylib PRIVATE SUPPORT_FILEFORMAT_JPG=1)
        endif()
        set(OLLIN_GRAPHICS_SOURCE src/modules/graphics_module.cpp src/modules/graphics3d.cpp src/modules/graphics_quat.cpp src/modules/keyboard_module.cpp src/modules/mouse_module.cpp src/modules/image_module.cpp)
        set(OLLIN_GRAPHICS_LIB raylib)
        set(OLLIN_GRAPHICS_DEFINES OLLIN_HAS_RAYLIB)
    else()
        message(STATUS "Native build with graphics stub (no window). Set -DOLLIN_NATIVE_RAYLIB=ON for raylib.")
        set(OLLIN_GRAPHICS_SOURCE src/modules/graphics_stub.cpp src/modules/image_stub.cpp)
        set(OLLIN_GRAPHICS_LIB "")
        set(OLLIN_GRAPHICS_DEFINES "")
    endif()

    add_executable(ollin src/main.cpp ${OLLIN_SOURCES} ${OLLIN_GRAPHICS_SOURCE} src/modules/window_module.cpp)
    target_compile_definitions(ollin PRIVATE ${OLLIN_GRAPHICS_DEFINES})
    target_include_directories(ollin PRIVATE src libs)
    target_link_libraries(ollin PRIVATE ${OLLIN_GRAPHICS_LIB})
    if(WIN32)
        target_link_libraries(ollin PRIVATE psapi)   # GetProcessMemoryInfo (mem())
    endif()
    target_compile_options(ollin PRIVATE -Wall -Wextra)
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        set_source_files_properties(src/vm.cpp PROPERTIES COMPILE_OPTIONS "-Og")
    endif()

    find_program(EMCC emcc)
    if(EMCC)
        set(WASM_SOURCES ${OLLIN_SOURCES} src/wasm_main.cpp src/modules/graphics_module.cpp src/modules/graphics3d.cpp src/modules/graphics_quat.cpp src/modules/keyboard_module.cpp src/modules/mouse_module.cpp src/modules/window_module.cpp src/modules/image_module.cpp)
        add_custom_command(
            OUTPUT  ${CMAKE_CURRENT_SOURCE_DIR}/docs/wasm/ollin.wasm
            DEPENDS ${WASM_SOURCES}
            COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tools/build-wasm.sh
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            COMMENT "Building WASM"
        )
        add_custom_target(wasm ALL
            DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/docs/wasm/ollin.wasm ollin
        )
    endif()
endif()
