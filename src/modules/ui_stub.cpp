#include "ui_module.h"

// Build sans raylib : les widgets n'ont pas de zone où se dessiner. Les déclarer ne
// lève pas — un script utilitaire peut ainsi tourner en natif headless —, elles ne
// font simplement rien.
Value make_ui_module() {
    Value m = Value::make_map();
    // Les arguments sont VALIDÉS quand même (mêmes messages, cf. ui_module.h) : une
    // faute d'appel se voit en natif headless, là où tournent les tests.
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
