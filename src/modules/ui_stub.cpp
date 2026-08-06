#include "ui_module.h"
#include "vm.h"

// Build sans raylib : aucune zone où dessiner, donc déclarer un widget ne produit
// rien de visible. Les arguments sont tout de même VÉRIFIÉS (mêmes messages, cf.
// ui_module.h) : une faute d'appel se voit ainsi en natif headless, là où tournent
// les tests. Les déclarations renvoient un handle inerte, avec les mêmes méthodes,
// pour qu'un script chaînant `ui.menu("x").button(...)` tourne aussi sans graphisme.

namespace {

Value inert_class();

Value make_inert() {
    Value h = Value::make_map();
    h.map_set(Value(std::string("__class__")), inert_class());
    return h;
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
    ui_slider_init(ctx.args + 1, ctx.argc - 1);
    return ctx.ret(make_inert());
}

int stub_menu(CallCtx& ctx) {
    ui_check_menu_args(ctx.args + 1, ctx.argc - 1);
    return ctx.ret(make_inert());
}

int stub_self(CallCtx& ctx) {
    return ctx.ret(ctx.args[0]);
}

Value make_inert_class() {
    Value cls = Value::make_class();
    cls.map_set(Value(std::string("__name__")), Value(std::string("UiElement")));
    cls.map_set(Value(std::string("button")), Value::make_builtin(stub_button));
    cls.map_set(Value(std::string("checkbox")), Value::make_builtin(stub_checkbox));
    cls.map_set(Value(std::string("slider")), Value::make_builtin(stub_slider));
    cls.map_set(Value(std::string("menu")), Value::make_builtin(stub_menu));
    cls.map_set(Value(std::string("open")), Value::make_builtin(stub_self));
    cls.map_set(Value(std::string("clear")), Value::make_builtin(stub_self));
    cls.map_set(Value(std::string("remove")), Value::make_builtin([](CallCtx& ctx) -> int {
        return ctx.ret(Value{});
    }));
    return cls;
}

Value inert_class() {
    static Value cls = make_inert_class();
    return cls;
}

int nothing(CallCtx& ctx) {
    return ctx.ret(Value{});
}

} // namespace

Value make_ui_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("button")), Value::make_builtin([](CallCtx& ctx) -> int {
        ui_check_button_args(ctx.args, ctx.argc);
        return ctx.ret(make_inert());
    }));
    m.map_set(Value(std::string("checkbox")), Value::make_builtin([](CallCtx& ctx) -> int {
        ui_check_checkbox_args(ctx.args, ctx.argc);
        return ctx.ret(make_inert());
    }));
    m.map_set(Value(std::string("slider")), Value::make_builtin([](CallCtx& ctx) -> int {
        ui_check_slider_args(ctx.args, ctx.argc);
        ui_slider_init(ctx.args, ctx.argc);
        return ctx.ret(make_inert());
    }));
    m.map_set(Value(std::string("menu")), Value::make_builtin([](CallCtx& ctx) -> int {
        ui_check_menu_args(ctx.args, ctx.argc);
        return ctx.ret(make_inert());
    }));
    m.map_set(Value(std::string("show")), Value::make_builtin(nothing));
    m.map_set(Value(std::string("back")), Value::make_builtin(nothing));
    m.map_set(Value(std::string("current")), Value::make_builtin([](CallCtx& ctx) -> int {
        return ctx.ret(make_inert());
    }));
    m.map_set(Value(std::string("clear")), Value::make_builtin(nothing));
    return m;
}

bool ui_poll() {
    return false;
}
void ui_draw() {
}
void ui_reset() {
}
