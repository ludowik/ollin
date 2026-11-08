#pragma once
#include "chunk.h"
#include "modules/module_utils.h"
#include "vm.h"
#include <algorithm>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

Value make_ui_module();

// Called by the render loop (graphics_module.cpp):
// ui_poll()  BEFORE mouse_poll; returns true when a widget took the click, in which case the click
//            must NOT reach the script's mouse.* callbacks.
// ui_draw()  AFTER the frame is composed (inside the drawing area, so the interface is independent of the
//            viewport) and before a screenshot is taken; paints the widget stack over the scene.
// ui_reset() when a PROGRAM starts (ollin_run, wasm_main.cpp) — NOT in gfx_run: widgets are declared
//            at file level, hence BEFORE graphics.run, and a reset there would erase them all. It is
//            needed because the statics survive the VM between two playground runs. ui.clear() calls
//            it too, which also folds the interface back to its handle.
bool ui_poll();
void ui_draw();
void ui_reset();

// Text entry (ui.textField), where the ui module meets the keyboard module. Only the raylib build has them: the stub has
// no field to edit, and keyboard_module.cpp is itself part of that build only.
// ui_editing()    a field is being edited. keyboard_poll then hands it the text and the control keys INSTEAD of the
//                 script's keyboard.typed / keypressed, and keyboard.isDown answers false. It also ends an edit whose
//                 field is no longer on display (removed, interface folded, another menu shown), without writing.
// ui_wants_text() a field exists, which is what makes a phone's page take the focus when the canvas is touched.
// ui_edit_text()  text typed while editing; ui_edit_key() a key NAME (return validates, escape cancels, backspace erases).
//                 Both return whether a field took it: false means nothing was being edited, and the caller keeps it.
bool ui_editing();
bool ui_wants_text();
bool ui_edit_text(const std::string& text);
bool ui_edit_key(const std::string& name);

// Argument validation, SHARED by the module and the stub.
// A misuse must be reported even without raylib, since the test binary uses the stub, so the
// messages live in a single place and cannot diverge. `args` and `argc` are the USER arguments: on a
// method call the receiver (self) has already been removed by the caller.
inline void ui_check_button_args(const Value* args, int argc) {
    if (argc < 2)
        throw std::runtime_error("ui.button: expected label, function");
    if (!args[0].is_string())
        throw std::runtime_error("ui.button: label must be a string");
    if (!args[1].is_callable())
        throw std::runtime_error("ui.button: second argument must be a function");
}

inline void ui_check_checkbox_args(const Value* args, int argc) {
    if (argc < 2)
        throw std::runtime_error("ui.checkbox: expected label, ref variable");
    if (!args[0].is_string())
        throw std::runtime_error("ui.checkbox: label must be a string");
    if (!is_ref(args[1]))
        throw std::runtime_error("ui.checkbox: second argument must be a reference — write `ref myVariable`");
    if (argc > 2 && !args[2].is_nil() && !args[2].is_callable())
        throw std::runtime_error("ui.checkbox: third argument must be a function");
}

// ui.slider(label, ref v, min, max [, default] [, onChange]) — the last two arguments are
// recognized by their TYPE: a number is the default value, a function the change callback. No order
// is imposed, and none is ambiguous.
inline void ui_check_slider_args(const Value* args, int argc) {
    if (argc < 4)
        throw std::runtime_error("ui.slider: expected label, ref variable, min, max");
    if (!args[0].is_string())
        throw std::runtime_error("ui.slider: label must be a string");
    if (!is_ref(args[1]))
        throw std::runtime_error("ui.slider: second argument must be a reference — write `ref myVariable`");
    if (!args[2].is_number() || !args[3].is_number())
        throw std::runtime_error("ui.slider: min and max must be numbers");
    if (args[2].as_num() >= args[3].as_num())
        throw std::runtime_error("ui.slider: min must be smaller than max");
    for (int i = 4; i < argc; ++i) {
        if (!args[i].is_nil() && !args[i].is_number() && !args[i].is_callable())
            throw std::runtime_error("ui.slider: extra argument must be a number (default) or a function");
    }
}

// A slider's default: the first numeric argument after max, or min when there is none.
inline Value ui_slider_default(const Value* args, int argc) {
    for (int i = 4; i < argc; ++i) {
        if (args[i].is_number())
            return args[i];
    }
    return args[2];
}

// ui.textField(label, ref v [, maxLength] [, placeholder] [, onSubmit]) — the three optional arguments are recognized by
// their TYPE, as a slider's are: a number is the maximum length in CHARACTERS, a string the placeholder shown while the
// text is empty, a function the callback called with the text when it is validated.
inline void ui_check_text_field_args(const Value* args, int argc) {
    if (argc < 2)
        throw std::runtime_error("ui.textField: expected label, ref variable");
    if (!args[0].is_string())
        throw std::runtime_error("ui.textField: label must be a string");
    if (!is_ref(args[1]))
        throw std::runtime_error("ui.textField: second argument must be a reference — write `ref myVariable`");
    for (int i = 2; i < argc; ++i) {
        if (args[i].is_nil() || args[i].is_string() || args[i].is_callable())
            continue;
        if (!args[i].is_number())
            throw std::runtime_error("ui.textField: extra argument must be a number (maximum length), a string (placeholder) or a function");
        if (!args[i].is_integer() || args[i].as_num() < 1)
            throw std::runtime_error("ui.textField: maximum length must be a positive integer");
    }
}

struct UiTextFieldOptions {
    size_t max_chars = 0;   // 0 = no limit
    std::string placeholder;
    Value on_submit;
};

inline UiTextFieldOptions ui_text_field_options(const Value* args, int argc) {
    UiTextFieldOptions out;
    for (int i = 2; i < argc; ++i) {
        if (args[i].is_number())
            out.max_chars = (size_t)args[i].as_num();
        else if (args[i].is_string())
            out.placeholder = args[i].as_string();
        else if (args[i].is_callable())
            out.on_submit = args[i];
    }
    return out;
}

// A text field's variable holds a string; nil is INITIALIZED to "" so the script can read it from the first frame on, as
// with a slider. Anything else is refused at declaration. By value, like ui_slider_init (reading runs script code).
inline void ui_text_init(Value target) {
    Value current = ref_get(target);
    if (current.is_nil())
        ref_set(target, Value(std::string()));
    else if (!current.is_string())
        throw std::runtime_error("ui.textField: the variable must hold a string (or nil)");
}

// A bound variable holding nil is INITIALIZED at declaration time, so the script can read it from
// the first frame on. Shared with the stub, which has no rendering but must give the script the same
// value. The reference and the default are taken BY VALUE, never as `args` pointers: reading or writing
// a reference runs script code, which can grow the register file and leave `args` dangling.
inline void ui_slider_init(Value target, const Value& default_value) {
    if (ref_get(target).is_nil())
        ref_set(target, default_value);
}

// A list's items: the LABEL displayed and the VALUE returned. An array gives its values, a map (or
// an enum) its keys — the same rule as `for … in`, whose single variable receives an array's value
// and a map's key.
//
// The ORDER is fixed here, because a map has none: an enum is sorted by value, which restores the
// declaration order, and an ordinary map by label, for want of anything better. Without this the
// list would reorder itself from one opening to the next.
inline std::vector<std::pair<std::string, Value>> ui_list_items(const Value& source) {
    std::vector<std::pair<std::string, Value>> out;
    if (source.is_array()) {
        int64_t n = source.array_size();
        for (int64_t i = 1; i <= n; i++) {
            Value v = source.array_get(i);
            out.push_back({value_to_string(v), v});
        }
        return out;
    }
    // The keys are collected BEFORE any label: value_to_string may call a key's __str meta-method,
    // hence Ollin code, which could mutate the map and invalidate the iterator mid-loop.
    bool by_value = source.as_map()->kind == Map::ENUM;
    std::vector<Value> keys;
    for (const auto& kv : source.as_map()->data) {
        if (!kv.second.is_number())
            by_value = false;
        keys.push_back(kv.first);
    }
    for (const auto& k : keys)
        out.push_back({value_to_string(k), k});
    if (by_value) {
        std::sort(out.begin(), out.end(), [&](const auto& a, const auto& b) {
            return source.map_get(a.second).as_num() < source.map_get(b.second).as_num();
        });
    } else {
        std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) {
            return a.first < b.first;
        });
    }
    return out;
}

inline void ui_check_list_args(const Value* args, int argc) {
    if (argc < 3)
        throw std::runtime_error("ui.list: expected label, array|map|enum, ref variable");
    if (!args[0].is_string())
        throw std::runtime_error("ui.list: label must be a string");
    if (!args[1].is_array() && !args[1].is_map())
        throw std::runtime_error("ui.list: second argument must be an array, a map or an enum");
    if (args[1].is_array() ? args[1].array_size() == 0 : args[1].map_size() == 0)
        throw std::runtime_error("ui.list: the list is empty");
    if (!is_ref(args[2]))
        throw std::runtime_error("ui.list: third argument must be a reference — write `ref myVariable`");
    if (argc > 3 && !args[3].is_nil() && !args[3].is_callable())
        throw std::runtime_error("ui.list: fourth argument must be a function");
}

// A list is SINGLE-selection: one item is always chosen. A variable bound to nil is therefore
// initialized to the first item, just as a slider takes its default. By value, like ui_slider_init.
inline void ui_list_init(Value target, Value source) {
    if (!ref_get(target).is_nil())
        return;
    auto items = ui_list_items(source);
    if (!items.empty())
        ref_set(target, items[0].second);
}

inline void ui_check_menu_args(const Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("ui.menu: expected label");
    if (!args[0].is_string())
        throw std::runtime_error("ui.menu: label must be a string");
}
