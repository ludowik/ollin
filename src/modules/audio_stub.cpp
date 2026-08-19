#include "audio_module.h"
#include "module_utils.h"

// Session sonore, build SANS raylib : aucune sortie, donc aucun son audible. Le module
// existe tout de même en entier — contrairement à `graphics`, qui vaut nil — parce que la
// génération d'ondes est un pur calcul : elle tourne ici à l'identique, et c'est ce qui
// rend la synthèse testable dans un conteneur sans carte son.
//
// Le volume est conservé pour que la lecture d'`audio.volume()` rende ce que le script a
// écrit : un accesseur qui oublie sa valeur ferait échouer un test pour la mauvaise raison.

namespace {

double s_volume = 1.0;

int stub_start(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(false));
}

int stub_is_ready(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(false));
}

int stub_volume(CallCtx& ctx) {
    audio_check_volume_args(ctx.args, ctx.argc);
    if (ctx.argc >= 1 && ctx.args[0].is_number())
        s_volume = audio_clamp_volume(ctx.args[0].as_num());
    return ctx.ret(Value(s_volume));
}

int stub_sample_rate(CallCtx& ctx) {
    return ctx.ret(Value((int64_t)k_audio_sample_rate));
}

} // namespace

void audio_wake() {
}

void audio_update() {
}

void audio_reset() {
    s_volume = 1.0;
}

Value make_audio_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("start")), Value::make_builtin(stub_start));
    m.map_set(Value(std::string("isReady")), Value::make_builtin(stub_is_ready));
    m.map_set(Value(std::string("volume")), Value::make_builtin(stub_volume));
    m.map_set(Value(std::string("sampleRate")), Value::make_builtin(stub_sample_rate));
    return m;
}
