#include "audio_module.h"
#include "module_utils.h"
#include "sound_internal.h"

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

// La pause appartient à la SESSION et non à chaque son : c'est l'équivalent sonore de la
// pause d'une boucle de rendu. Elle suspend l'avancement, là où un volume à zéro laisserait
// tout courir en silence et ferait reprendre le son plus loin qu'on l'a laissé.
int stub_pause(CallCtx& ctx) {
    sound_set_paused(true);
    return ctx.ret(Value{});
}

int stub_resume(CallCtx& ctx) {
    sound_set_paused(false);
    return ctx.ret(Value{});
}

int stub_is_paused(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(sound_paused()));
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
    m.map_set(Value(std::string("pause")), Value::make_builtin(stub_pause));
    m.map_set(Value(std::string("resume")), Value::make_builtin(stub_resume));
    m.map_set(Value(std::string("isPaused")), Value::make_builtin(stub_is_paused));
    m.map_set(Value(std::string("sampleRate")), Value::make_builtin(stub_sample_rate));
    return m;
}
