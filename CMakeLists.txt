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

# Native build WITH raylib, hence with a window and graphics, instead of the stub. OFF by
# default: the standard native build stays headless-safe, which the remote environments need,
# having no network access to raylib. Turn it on locally with -DOLLIN_NATIVE_RAYLIB=ON (a CMake
# cache local to build/, not shared) or through tools/native-gfx.sh (build-gfx/, the Xvfb tests).
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
    src/modules/array_module.cpp
    src/modules/data_module.cpp
    src/modules/tween_module.cpp
    src/modules/sound_module.cpp
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

    # raylib disables JPG by default (config.h: SUPPORT_FILEFORMAT_JPG 0).
    # On l'active pour que image.load accepte les .jpg/.jpeg — sans modifier la
    # source raylib : la valeur 1 l'emporte sur le #ifndef de config.h, ce qui
    # avoids the #define STBI_NO_JPEG of rtextures.c.
    if(TARGET raylib)
        target_compile_definitions(raylib PRIVATE SUPPORT_FILEFORMAT_JPG=1)
    endif()

    add_executable(ollin_wasm src/wasm_main.cpp ${OLLIN_SOURCES} src/modules/graphics_module.cpp src/modules/graphics3d.cpp src/modules/graphics_quat.cpp src/modules/keyboard_module.cpp src/modules/mouse_module.cpp src/modules/window_module.cpp src/modules/image_module.cpp src/modules/ui_module.cpp src/modules/engine_font.cpp src/modules/camera_module.cpp src/modules/audio_module.cpp src/modules/sound_output.cpp src/modules/touch_module.cpp)
    target_include_directories(ollin_wasm PRIVATE src libs)
    target_compile_options(ollin_wasm PRIVATE -Wall -Wextra -fexceptions)
    set_target_properties(ollin_wasm PROPERTIES OUTPUT_NAME "ollin" SUFFIX ".js")
    target_link_libraries(ollin_wasm PRIVATE raylib)
    target_link_options(ollin_wasm PRIVATE
        -sMODULARIZE=1
        -sEXPORT_NAME=OllinModule
        # FIXED memory, with no growth — MANDATORY for iOS and WebKit. Since emsdk
        # 6.0.x, with ALLOW_MEMORY_GROWTH the WASM memory is a resizable ArrayBuffer
        # *redimensionnable* quand le navigateur le supporte. Or WebKit REFUSE une
        # typed view over a resizable ArrayBuffer as an argument to
        # glTexImage2D, hence "srcData must be an instance of ArrayBufferView" on EVERY
        # texture upload: every graphics script crashes on iOS, while Chrome tolerates it, hence
        # an iOS-only bug. Fixed memory guarantees an ordinary ArrayBuffer, whose views
        # are accepted. 128 MB is roomy for the playground: the interpreter plus
        # raylib, about 40 MB, plus the user's data.
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
        # raylib comes from libs/raylib when it exists, otherwise from FetchContent, which reuses
        # the cache when -DFETCHCONTENT_SOURCE_DIR_RAYLIB=<src> is passed; see native-gfx.sh.
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
        # Enables JPG and JPEG decoding in raylib, which is off by default.
        if(TARGET raylib)
            target_compile_definitions(raylib PRIVATE SUPPORT_FILEFORMAT_JPG=1)
        endif()
        set(OLLIN_GRAPHICS_SOURCE src/modules/graphics_module.cpp src/modules/graphics3d.cpp src/modules/graphics_quat.cpp src/modules/keyboard_module.cpp src/modules/mouse_module.cpp src/modules/image_module.cpp src/modules/ui_module.cpp src/modules/engine_font.cpp src/modules/camera_stub.cpp src/modules/audio_module.cpp src/modules/sound_output.cpp src/modules/touch_module.cpp)
        set(OLLIN_GRAPHICS_LIB raylib)
        set(OLLIN_GRAPHICS_DEFINES OLLIN_HAS_RAYLIB)
    else()
        message(STATUS "Native build with graphics stub (no window). Set -DOLLIN_NATIVE_RAYLIB=ON for raylib.")
        set(OLLIN_GRAPHICS_SOURCE src/modules/graphics_stub.cpp src/modules/image_stub.cpp src/modules/ui_stub.cpp src/modules/camera_stub.cpp src/modules/audio_stub.cpp src/modules/sound_output_stub.cpp src/modules/touch_stub.cpp)
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
        set(WASM_SOURCES ${OLLIN_SOURCES} src/wasm_main.cpp src/modules/graphics_module.cpp src/modules/graphics3d.cpp src/modules/graphics_quat.cpp src/modules/keyboard_module.cpp src/modules/mouse_module.cpp src/modules/window_module.cpp src/modules/image_module.cpp src/modules/ui_module.cpp src/modules/engine_font.cpp src/modules/audio_module.cpp src/modules/sound_output.cpp src/modules/touch_module.cpp)
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
