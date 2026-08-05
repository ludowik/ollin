#include "ui_module.h"

// Build sans raylib : aucune zone où dessiner, donc déclarer un widget ne produit
// rien de visible. Les arguments sont tout de même VÉRIFIÉS (mêmes messages, cf.
// ui_module.h) : une faute d'appel se voit ainsi en natif headless, là où tournent
// les tests.
Value make_ui_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("button")), Value::make_builtin([](CallCtx& ctx) -> int {
        ui_check_button_args(ctx.args, ctx.argc);
        return ctx.ret(Value{});
    }));
    m.map_set(Value(std::string("checkbox")), Value::make_builtin([](CallCtx& ctx) -> int {
        ui_check_checkbox_args(ctx.args, ctx.argc);
        return ctx.ret(Value{});
    }));
    m.map_set(Value(std::string("clear")), Value::make_builtin([](CallCtx& ctx) -> int {
        return ctx.ret(Value{});
    }));
    return m;
}

bool ui_poll() {
    return false;
}
void ui_draw() {
}
void ui_reset() {
}
