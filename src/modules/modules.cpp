#include "modules.h"
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
Value make_date_module();

static const struct { const char* name; Value(*make)(); } k_modules[] = {
    { "core",     make_core_module     },
    { "math",     make_math_module     },
    { "graphics", make_graphics_module },
    { "string",   make_string_module   },
    { "colors",   make_colors_module   },
    { "blend",    make_blend_module    },
    { "window",   make_window_module   },
    { "image",    make_image_module    },
    { "keyboard", make_keyboard_module },
    { "mouse",    make_mouse_module    },
    { "data",     make_data_module     },
    { "camera",   make_camera_module   },
    { "ui",       make_ui_module       },
    { "tween",    make_tween_module    },
    { "audio",    make_audio_module    },
    { "sound",    make_sound_module    },
    { "touch",    make_touch_module    },
    { "date",     make_date_module     },
};

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
        if (name == m.name)
            return m.make();
    throw std::runtime_error("unknown built-in module: " + name);
}
