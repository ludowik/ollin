#include "ui_module.h"
#include "module_utils.h"
#include "vm.h"

// Build without raylib: there is no area to draw in, so declaring a widget produces nothing
// visible. The arguments are still VALIDATED, with the same messages (see ui_module.h), so a
// misuse shows up in the headless native build where the tests run. Declarations return an inert
// handle carrying the same methods, so that a script chaining ui.menu("x").button(...) runs
// without graphics too.

namespace {

Value inert_class();

Value make_inert() {
    return MapBuilder()
        .set("__class__", inert_class())
        .done();
}

int stub_button(CallCtx& ctx) {
    ui_check_button_args(ctx.args + 1, ctx.argc - 1);
    return ctx.ret(make_inert());
}

int stub_checkbox(CallCtx& ctx) {
    ui_check_checkbox_args(ctx.args + 1, ctx.argc - 1);
    return ctx.ret(make_inert());
}

int stub_slider(CallCtx& ctx) {
    ui_check_slider_args(ctx.args + 1, ctx.argc - 1);
    Value target = ctx.args[2];
    Value default_value = ui_slider_default(ctx.args + 1, ctx.argc - 1);
    ui_slider_init(target, default_value);
    return ctx.ret(make_inert());
}

int stub_list(CallCtx& ctx) {
    ui_check_list_args(ctx.args + 1, ctx.argc - 1);
    ui_list_init(ctx.args[3], ctx.args[2]);
    return ctx.ret(make_inert());
}

int stub_menu(CallCtx& ctx) {
    ui_check_menu_args(ctx.args + 1, ctx.argc - 1);
    return ctx.ret(make_inert());
}

int stub_self(CallCtx& ctx) {
    return ctx.ret(ctx.args[0]);
}

int nothing(CallCtx& ctx) {
    return ctx.ret(Value{});
}

Value make_inert_class() {
    return MapBuilder(Value::make_class())
        .str("__name__", "UiElement")
        .fn("button", stub_button)
        .fn("checkbox", stub_checkbox)
        .fn("slider", stub_slider)
        .fn("list", stub_list)
        .fn("menu", stub_menu)
        .fn("open", stub_self)
        .fn("clear", stub_self)
        .fn("remove", nothing)
        .done();
}

Value inert_class() {
    static Value cls = make_inert_class();
    return cls;
}

int module_button(CallCtx& ctx) {
    ui_check_button_args(ctx.args, ctx.argc);
    return ctx.ret(make_inert());
}

int module_checkbox(CallCtx& ctx) {
    ui_check_checkbox_args(ctx.args, ctx.argc);
    return ctx.ret(make_inert());
}

int module_slider(CallCtx& ctx) {
    ui_check_slider_args(ctx.args, ctx.argc);
    Value target = ctx.args[1];
    Value default_value = ui_slider_default(ctx.args, ctx.argc);
    ui_slider_init(target, default_value);
    return ctx.ret(make_inert());
}

int module_list(CallCtx& ctx) {
    ui_check_list_args(ctx.args, ctx.argc);
    ui_list_init(ctx.args[2], ctx.args[1]);
    return ctx.ret(make_inert());
}

int module_menu(CallCtx& ctx) {
    ui_check_menu_args(ctx.args, ctx.argc);
    return ctx.ret(make_inert());
}

int module_current(CallCtx& ctx) {
    return ctx.ret(make_inert());
}

} // namespace

Value make_ui_module() {
    return MapBuilder()
        .fn("button", module_button)
        .fn("checkbox", module_checkbox)
        .fn("slider", module_slider)
        .fn("list", module_list)
        .fn("menu", module_menu)
        .fn("show", nothing)
        .fn("open", nothing)
        .fn("close", nothing)
        .fn("toggle", nothing)
        .fn("back", nothing)
        .fn("current", module_current)
        .fn("clear", nothing)
        .done();
}

bool ui_poll() {
    return false;
}
void ui_draw() {
}
void ui_reset() {
}
