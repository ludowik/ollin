#include "modules.h"
#include "audio_module.h"
#include "camera_module.h"
#include "https_module.h"
#include "image_module.h"
#include "map_module.h"
#include "motion_module.h"
#include "mouse_module.h"
#include "sound_module.h"
#include "touch_module.h"
#include "tween_module.h"
#include "ui_module.h"
#include "value.h"
#include <stdexcept>

Value make_core_module();
Value make_math_module();
Value make_graphics_module();
// The `blend` module is defined in the graphics pair (graphics_module holds the enums
// raylib BlendMode / graphics_stub → nil) and NOT here: modules.cpp compiles
// without raylib too, and so cannot reference the enum. See make_graphics_module.
Value make_blend_module();
Value make_string_module();
Value make_colors_module();
Value make_window_module();
Value make_image_module();
Value make_keyboard_module();
Value make_mouse_module();
Value make_data_module();
Value make_camera_module();
Value make_ui_module();
Value make_tween_module();
Value make_audio_module();
Value make_sound_module();
Value make_touch_module();
Value make_motion_module();
Value make_date_module();
Value make_json_module();
Value make_https_module();

// graphics_internal.h pulls in raylib, which this file compiles without: the one function it needs is declared here
// (graphics_module.cpp, or graphics_stub.cpp without a window).
void gfx_program_reset();

// A module that keeps state from one frame to the next says here how to forget it: `reset` runs when a new program
// starts (modules_reset), because the statics outlive the VM and the next program must not inherit the last one's
// animations, widgets, requests, fingers or sounds. Every build has one, a stub's included, so that a module is
// declared in one place and a new one cannot be forgotten in the engine's entry point. What runs every frame stays
// written out in the render loop, where the ORDER of the calls is documented.
static const struct { const char* name; Value(*make)(); void(*reset)(); } k_modules[] = {
    { "core",     make_core_module,     nullptr          },
    { "math",     make_math_module,     nullptr          },
    { "graphics", make_graphics_module, gfx_program_reset },   // fitArea off, the orientation lock released
    { "string",   make_string_module,   nullptr          },
    { "map",      make_map_module,      nullptr          },
    { "colors",   make_colors_module,   nullptr          },
    { "blend",    make_blend_module,    nullptr          },
    { "window",   make_window_module,   nullptr          },
    { "image",    make_image_module,    image_reset      },   // stale GL texture handles, before the context may be reset
    { "keyboard", make_keyboard_module, nullptr          },
    { "mouse",    make_mouse_module,    mouse_reset      },   // no button left pressed
    { "data",     make_data_module,     nullptr          },
    { "camera",   make_camera_module,   camera_reset     },
    { "ui",       make_ui_module,       ui_reset         },
    { "tween",    make_tween_module,    tween_reset      },
    { "audio",    make_audio_module,    audio_reset      },   // the master volume a program may have turned down
    { "sound",    make_sound_module,    sound_reset      },
    { "touch",    make_touch_module,    touch_reset      },   // a finger left "down" would look like a gesture
    { "motion",   make_motion_module,   motion_reset     },   // a program asks for the sensors itself
    { "date",     make_date_module,     nullptr          },
    { "json",     make_json_module,     nullptr          },
    { "https",    make_https_module,    https_reset      },   // an answer still on its way would reach the wrong program
};

void modules_reset() {
    for (auto& m : k_modules) {
        if (m.reset)
            m.reset();
    }
}

const std::vector<std::string>& builtin_module_names() {
    static const std::vector<std::string> names = [] {
        std::vector<std::string> v;
        for (auto& m : k_modules)
            v.push_back(m.name);
        return v;
    }();
    return names;
}

const std::vector<std::string>& builtin_func_names() {
    static const std::vector<std::string> names = {"print", "printf", "__fmt", "typeof", "assert",
                                                   "time", "cpuTime", "mem", "Color", "len"};
    return names;
}

Value make_builtin_module(const std::string& name) {
    for (auto& m : k_modules)
        if (name == m.name) {
            Value mod = m.make();
            // The single point where a built-in module's root map is marked as such (Map::kind,
            // see the comment on it) — never propagated to whatever the module contains.
            if (mod.is_map())
                mod.mptr->kind = Map::MODULE;
            return mod;
        }
    throw std::runtime_error("unknown built-in module: " + name);
}
