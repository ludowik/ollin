#include "sound_module.h"
#include "audio_module.h"
#include "module_utils.h"
#include "sound_internal.h"
#include <string>

// Module `sound` : l'API et l'état, dans TOUS les builds. La sortie, elle, dépend de
// raylib (sound_output.cpp / sound_output_stub.cpp) — voir sound_internal.h.
//
// Un oscillateur est une VOIX dans une table fixe. Le script n'en manipule qu'un handle
// {slot, gen}, jamais un pointeur : `gen` détecte un handle périmé au lieu de désigner la
// voix qui a recyclé le slot.

namespace {

Voice* voices() {
    return sound_voices();
}

Value osc_class();

Value make_handle(int slot) {
    Value h = Value::make_map();
    h.map_set(Value(std::string("__class__")), osc_class());
    h.map_set(Value(std::string("slot")), Value((int64_t)slot));
    h.map_set(Value(std::string("gen")), Value((int64_t)voices()[slot].gen));
    return h;
}

int handle_slot(const Value& self, const char* fn) {
    Value slot = self.map_get(Value(std::string("slot")));
    Value gen = self.map_get(Value(std::string("gen")));
    if (!slot.is_integer() || !gen.is_integer())
        throw std::runtime_error(std::string(fn) + ": expected an oscillator");
    int i = (int)slot.as_int();
    if (i < 0 || i >= k_max_voices || voices()[i].gen != (uint32_t)gen.as_int())
        throw std::runtime_error(std::string(fn) + ": cet oscillateur n'existe plus");
    return i;
}

// Un slot libre, sinon la voix ARRÊTÉE la plus ANCIENNE : le script n'a aucun moyen de
// rendre un oscillateur (il n'y a pas de finaliseur), donc un programme qui en crée à la
// demande épuiserait la table sans ce recyclage. Une voix qui sonne n'est jamais volée.
//
// Le rang de création décide, et non le premier slot venu : « le premier arrêté » martelait
// toujours la voix 0 et ne touchait jamais les autres, si bien qu'un oscillateur pouvait
// survivre à vingt créations quand son voisin ne survivait pas à une seule (constaté).
uint64_t s_born_counter = 0;

int alloc_voice() {
    Voice* v = voices();
    for (int i = 0; i < k_max_voices; i++) {
        if (!v[i].used)
            return i;
    }
    int choisi = -1;
    for (int i = 0; i < k_max_voices; i++) {
        if (v[i].active.load(std::memory_order_relaxed) || v[i].gain > 0.0f)
            continue;
        if (choisi < 0 || v[i].born < v[choisi].born)
            choisi = i;
    }
    if (choisi >= 0) {
        v[choisi].gen++;
        return choisi;
    }
    throw std::runtime_error("sound: plus d'oscillateur disponible (" + std::to_string(k_max_voices) +
                             " en même temps, tous en train de sonner)");
}

int make_osc(const Value* args, int argc, const char* fn, int shape_forced) {
    double hz = sound_check_freq(args, argc, 0, fn);
    int shape = shape_forced >= 0 ? shape_forced : sound_check_shape(args, argc, 1, fn);
    int slot = alloc_voice();
    Voice& v = voices()[slot];
    v.used = true;
    v.born = ++s_born_counter;
    v.active.store(false, std::memory_order_relaxed);
    v.shape.store(shape, std::memory_order_relaxed);
    v.freq.store((float)(hz < 0.0 ? 440.0 : hz), std::memory_order_relaxed);
    v.volume.store(0.5f, std::memory_order_relaxed);
    v.pan.store(0.0f, std::memory_order_relaxed);
    v.gain = 0.0f;
    v.phase = 0.0;
    return slot;
}

int sound_osc(CallCtx& ctx) {
    return ctx.ret(make_handle(make_osc(ctx.args, ctx.argc, "sound.osc", -1)));
}

// Raccourcis par forme d'onde, comme p5 : plus lisibles qu'un nom passé en chaîne, et un
// nom fautif y devient impossible.
template <int SHAPE>
int sound_shape_factory(CallCtx& ctx) {
    static const char* k_fn[] = {"sound.sine", "sound.square", "sound.saw", "sound.triangle", "sound.noise"};
    return ctx.ret(make_handle(make_osc(ctx.args, ctx.argc, k_fn[SHAPE], SHAPE)));
}

int method_start(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.start");
    audio_wake();   // démarrer un son demande implicitement le périphérique
    sound_output_ensure();
    voices()[i].active.store(true, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_stop(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.stop");
    voices()[i].active.store(false, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_is_playing(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.isPlaying");
    return ctx.ret(Value::make_bool(voices()[i].active.load(std::memory_order_relaxed)));
}

// Les accesseurs suivent la règle de `graphics.font` : sans argument ils LISENT, avec un
// argument ils écrivent et rendent le handle, ce qui permet de les chaîner.
int method_freq(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.freq");
    double hz = sound_check_freq(ctx.args + 1, ctx.argc - 1, 0, "sound.freq");
    if (hz < 0.0)
        return ctx.ret(Value((double)voices()[i].freq.load(std::memory_order_relaxed)));
    voices()[i].freq.store((float)hz, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_volume(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.volume");
    double v = sound_check_unit(ctx.args + 1, ctx.argc - 1, 0, "sound.volume", "le volume", 0.0);
    if (v < -1.0)
        return ctx.ret(Value((double)voices()[i].volume.load(std::memory_order_relaxed)));
    voices()[i].volume.store((float)v, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_pan(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.pan");
    double p = sound_check_unit(ctx.args + 1, ctx.argc - 1, 0, "sound.pan", "le panoramique", -1.0);
    if (p < -1.5)
        return ctx.ret(Value((double)voices()[i].pan.load(std::memory_order_relaxed)));
    voices()[i].pan.store((float)p, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_shape(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.shape");
    if (ctx.argc < 2 || ctx.args[1].is_nil())
        return ctx.ret(Value(std::string(sound_shape_name(voices()[i].shape.load(std::memory_order_relaxed)))));
    voices()[i].shape.store(sound_check_shape(ctx.args + 1, ctx.argc - 1, 0, "sound.shape"),
                            std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

Value make_osc_class() {
    Value cls = Value::make_class();
    cls.map_set(Value(std::string("__name__")), Value(std::string("Osc")));
    cls.map_set(Value(std::string("start")), Value::make_builtin(method_start));
    cls.map_set(Value(std::string("stop")), Value::make_builtin(method_stop));
    cls.map_set(Value(std::string("isPlaying")), Value::make_builtin(method_is_playing));
    cls.map_set(Value(std::string("freq")), Value::make_builtin(method_freq));
    cls.map_set(Value(std::string("volume")), Value::make_builtin(method_volume));
    cls.map_set(Value(std::string("pan")), Value::make_builtin(method_pan));
    cls.map_set(Value(std::string("shape")), Value::make_builtin(method_shape));
    return cls;
}

Value osc_class() {
    static Value cls = make_osc_class();
    return cls;
}

} // namespace

// La table de voix vit ICI, dans le fichier compilé partout : la sortie n'y accède que par
// sound_voices(), donc le mélangeur n'a pas besoin de connaître le module.
Voice* sound_voices() {
    static Voice table[k_max_voices];
    return table;
}

void sound_reset() {
    Voice* v = sound_voices();
    for (int i = 0; i < k_max_voices; i++) {
        v[i].active.store(false, std::memory_order_relaxed);
        v[i].used = false;
        v[i].gen++;
    }
    sound_output_silence();
}

void sound_update() {
    sound_output_ensure();
}

Value make_sound_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("osc")), Value::make_builtin(sound_osc));
    m.map_set(Value(std::string("sine")), Value::make_builtin(sound_shape_factory<SHAPE_SINE>));
    m.map_set(Value(std::string("square")), Value::make_builtin(sound_shape_factory<SHAPE_SQUARE>));
    m.map_set(Value(std::string("saw")), Value::make_builtin(sound_shape_factory<SHAPE_SAW>));
    m.map_set(Value(std::string("triangle")), Value::make_builtin(sound_shape_factory<SHAPE_TRIANGLE>));
    m.map_set(Value(std::string("noise")), Value::make_builtin(sound_shape_factory<SHAPE_NOISE>));
    return m;
}
