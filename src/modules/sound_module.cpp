#include "sound_module.h"
#include "audio_module.h"
#include "module_utils.h"
#include "sound_internal.h"
#include <atomic>
#include <cmath>
#include <string>
#include <vector>

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
        throw std::runtime_error(std::string(fn) + ": this oscillator no longer exists");
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

bool voice_sounding(const Voice& v) {
    return v.active.load(std::memory_order_relaxed) || v.gain > 0.0f;
}

int alloc_voice() {
    Voice* v = voices();
    for (int i = 0; i < k_max_voices; i++) {
        // Rendue par `free` mais pas encore éteinte : le slot est libre, le SON non. La
        // reprendre couperait la queue de note que le script vient de relâcher.
        if (!v[i].used && !voice_sounding(v[i]))
            return i;
    }
    int chosen = -1;
    for (int i = 0; i < k_max_voices; i++) {
        if (voice_sounding(v[i]))
            continue;
        if (chosen < 0 || v[i].born < v[chosen].born)
            chosen = i;
    }
    if (chosen >= 0) {
        v[chosen].gen++;
        return chosen;
    }
    throw std::runtime_error("sound: no oscillator available (" + std::to_string(k_max_voices) +
                             " at a time, all still sounding)");
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
    v.freq.store(hz < 0.0 ? 440.0 : hz, std::memory_order_relaxed);
    v.volume.store(0.5, std::memory_order_relaxed);
    v.pan.store(0.0, std::memory_order_relaxed);
    v.gain = 0.0f;
    v.phase = 0.0;
    v.env_used.store(false, std::memory_order_relaxed);
    v.gate.store(false, std::memory_order_relaxed);
    v.env_hold.store(-1.0, std::memory_order_relaxed);
    return slot;
}

// La conversion est exposée telle quelle : un script qui construit une gamme a besoin du
// nombre, pas seulement d'un oscillateur.
int sound_note(CallCtx& ctx) {
    if (ctx.argc < 1 || !ctx.args[0].is_string())
        throw std::runtime_error("sound.note: expected a note name, like \"C#4\"");
    return ctx.ret(Value(sound_note_hz(ctx.args[0].as_string(), "sound.note")));
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
        return ctx.ret(Value(voices()[i].freq.load(std::memory_order_relaxed)));
    voices()[i].freq.store(hz, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_volume(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.volume");
    double v = sound_check_unit(ctx.args + 1, ctx.argc - 1, 0, "sound.volume", "volume", 0.0);
    if (v < -1.0)
        return ctx.ret(Value(voices()[i].volume.load(std::memory_order_relaxed)));
    voices()[i].volume.store(v, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_pan(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.pan");
    double p = sound_check_unit(ctx.args + 1, ctx.argc - 1, 0, "sound.pan", "pan", -1.0);
    if (p < -1.5)
        return ctx.ret(Value(voices()[i].pan.load(std::memory_order_relaxed)));
    voices()[i].pan.store(p, std::memory_order_relaxed);
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

// L'enveloppe est portée par l'oscillateur, et non par un objet séparé comme dans p5 : là
// elle peut moduler n'importe quel paramètre de Web Audio, ici elle n'a qu'une cible — le
// volume d'une voix. Un second type de handle n'apporterait donc rien à retenir.
int method_envelope(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.envelope");
    Voice& v = voices()[i];
    if (ctx.argc < 2) {
        Value m = Value::make_map();
        m.map_set(Value(std::string("attack")), Value(v.env_attack.load(std::memory_order_relaxed)));
        m.map_set(Value(std::string("decay")), Value(v.env_decay.load(std::memory_order_relaxed)));
        m.map_set(Value(std::string("sustain")), Value(v.env_sustain.load(std::memory_order_relaxed)));
        m.map_set(Value(std::string("release")), Value(v.env_release.load(std::memory_order_relaxed)));
        return ctx.ret(m);
    }
    sound_check_envelope(ctx.args + 1, ctx.argc - 1, "sound.envelope");
    v.env_attack.store(ctx.args[1].as_num(), std::memory_order_relaxed);
    v.env_decay.store(ctx.args[2].as_num(), std::memory_order_relaxed);
    v.env_sustain.store(ctx.args[3].as_num(), std::memory_order_relaxed);
    v.env_release.store(ctx.args[4].as_num(), std::memory_order_relaxed);
    v.env_used.store(true, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

// trigger([durée]) — joue la note. Sans durée elle est TENUE jusqu'à release() ; avec, le
// relâchement part tout seul à l'échéance, ce qui suffit pour un bip ou une note de mélodie.
int method_trigger(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.trigger");
    double hold = sound_check_hold(ctx.args + 1, ctx.argc - 1, "sound.trigger");
    Voice& v = voices()[i];
    v.env_used.store(true, std::memory_order_relaxed);
    v.env_hold.store(hold, std::memory_order_relaxed);
    v.gate.store(true, std::memory_order_relaxed);
    // Le compteur est incrémenté EN DERNIER : c'est lui que le mélangeur observe pour
    // repartir de l'attaque, et il doit trouver les autres paramètres déjà posés.
    v.trigger_id.fetch_add(1, std::memory_order_relaxed);
    audio_wake();
    sound_output_ensure();
    v.active.store(true, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_release(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.release");
    voices()[i].gate.store(false, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

// free() — « je n'en ai plus besoin ». Sans cela, un script ne pouvait PAS créer ses
// oscillateurs à la demande : `alloc_voice` reprend la voix arrêtée la plus ancienne, donc
// tout handle encore détenu risquait de désigner un slot recyclé (l'erreur est signalée, mais
// le programme est cassé). D'où le pool pré-alloué que tout script polyphonique devait écrire.
//
// La note n'est PAS coupée : on lâche l'enveloppe comme le ferait `release`, et le slot n'est
// rendu qu'à l'extinction — `alloc_voice` refuse déjà une voix dont le gain n'est pas retombé.
// Couper net produirait un clic, et perdrait la queue de note que le script vient de relâcher.
int method_free(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.free");
    Voice& v = voices()[i];
    v.gate.store(false, std::memory_order_relaxed);
    if (!v.env_used.load(std::memory_order_relaxed))
        v.active.store(false, std::memory_order_relaxed);   // sans enveloppe, rien à éteindre
    v.used = false;
    v.gen++;   // le handle devient périmé : le réutiliser est signalé, pas silencieux
    return ctx.ret(Value{});
}


// ── Tampons : un son CALCULÉ, qu'on déclenche ────────────────────────────────────
// Même patron que les voix : table fixe, handle {slot, gen}. La différence est la durée de
// vie des ÉCHANTILLONS, que le mélangeur lit depuis un autre fil — d'où le protocole de
// réutilisation décrit dans sound_internal.h.

Buf* bufs() {
    return sound_buffers();
}

Value buffer_class();

Value make_buffer_handle(int slot) {
    Value h = Value::make_map();
    h.map_set(Value(std::string("__class__")), buffer_class());
    h.map_set(Value(std::string("slot")), Value((int64_t)slot));
    h.map_set(Value(std::string("gen")), Value((int64_t)bufs()[slot].gen));
    return h;
}

int buffer_slot(const Value& self, const char* fn) {
    Value slot = self.map_get(Value(std::string("slot")));
    Value gen = self.map_get(Value(std::string("gen")));
    if (!slot.is_integer() || !gen.is_integer())
        throw std::runtime_error(std::string(fn) + ": expected a sound");
    int i = (int)slot.as_int();
    if (i < 0 || i >= k_max_buffers || bufs()[i].gen != (uint32_t)gen.as_int())
        throw std::runtime_error(std::string(fn) + ": this sound no longer exists");
    return i;
}

// Un slot libre, sinon le plus anciennement rendu — à condition qu'un bloc de mélange se
// soit écoulé depuis. Sans cette attente, un bloc déjà en cours pourrait lire les
// échantillons pendant qu'on les remplace.
int alloc_buffer() {
    Buf* b = bufs();
    for (int i = 0; i < k_max_buffers; i++) {
        if (!b[i].used)
            return i;
    }
    uint64_t maintenant = sound_mix_epoch();
    int chosen = -1;
    for (int i = 0; i < k_max_buffers; i++) {
        if (b[i].playing.load(std::memory_order_relaxed))
            continue;
        if (b[i].retired_epoch >= maintenant)
            continue;   // rendu trop récemment : un bloc peut encore le lire
        if (chosen < 0 || b[i].retired_epoch < b[chosen].retired_epoch)
            chosen = i;
    }
    if (chosen < 0)
        throw std::runtime_error("sound: no sound slot available (" + std::to_string(k_max_buffers) +
                                 " at a time)");
    b[chosen].gen++;
    return chosen;
}

int new_buffer(std::vector<float>&& samples) {
    int slot = alloc_buffer();
    Buf& b = bufs()[slot];
    b.used = true;
    b.samples = std::move(samples);
    b.playing.store(false, std::memory_order_relaxed);
    b.loop.store(false, std::memory_order_relaxed);
    b.volume.store(0.5, std::memory_order_relaxed);
    b.pan.store(0.0, std::memory_order_relaxed);
    b.rate.store(1.0, std::memory_order_relaxed);
    b.pos = 0.0;
    return slot;
}

// Forme d'onde échantillonnée hors ligne. C'est la MÊME table de formes que l'oscillateur,
// mais calculée ici une fois pour toutes : un tampon ne coûte plus rien à la lecture.
double wave_at(int shape, double phase, uint32_t& noise_state) {
    switch (shape) {
    case SHAPE_SQUARE:
        return phase < 0.5 ? 1.0 : -1.0;
    case SHAPE_SAW:
        return 2.0 * phase - 1.0;
    case SHAPE_TRIANGLE:
        return 1.0 - 4.0 * std::fabs(phase - 0.5);
    case SHAPE_NOISE:
        noise_state ^= noise_state << 13;
        noise_state ^= noise_state >> 17;
        noise_state ^= noise_state << 5;
        return (double)noise_state / 2147483648.0 - 1.0;
    default:
        return std::sin(phase * 6.283185307179586);
    }
}

int sound_tone(CallCtx& ctx) {
    const char* FN = "sound.tone";
    double hz = sound_check_freq(ctx.args, ctx.argc, 0, FN);
    if (hz < 0.0)
        throw std::runtime_error(std::string(FN) + ": expected a frequency as first argument");
    double duration = sound_check_duration(ctx.args, ctx.argc, 1, FN);
    int shape = sound_check_shape(ctx.args, ctx.argc, 2, FN);
    size_t n = (size_t)(duration * k_audio_sample_rate);
    std::vector<float> samples(n);
    double phase = 0.0;
    double avance = hz / (double)k_audio_sample_rate;
    uint32_t noise_state = 0x9e3779b9u;
    for (size_t i = 0; i < n; i++) {
        samples[i] = (float)wave_at(shape, phase, noise_state);
        phase += avance;
        if (phase >= 1.0)
            phase -= 1.0;
    }
    return ctx.ret(make_buffer_handle(new_buffer(std::move(samples))));
}

// La formule du script est échantillonnée UNE fois, ici, sur le fil principal : elle
// n'entre jamais dans le rappel audio, où exécuter du bytecode sous échéance dure
// s'entendrait comme un craquement.
int sound_generate(CallCtx& ctx) {
    const char* FN = "sound.generate";
    double duration = sound_check_duration(ctx.args, ctx.argc, 0, FN);
    if (ctx.argc < 2 || !ctx.args[1].is_callable())
        throw std::runtime_error(std::string(FN) + ": expected a second argument: a function of time");
    Value f = ctx.args[1];
    size_t n = (size_t)(duration * k_audio_sample_rate);
    std::vector<float> samples(n);
    VM* vm = VM::current();
    double pas = 1.0 / (double)k_audio_sample_rate;
    for (size_t i = 0; i < n; i++) {
        Value r = vm->call_value(f, Value((double)i * pas));
        // Une valeur non numérique vaut zéro : lever au 30 000ᵉ échantillon donnerait un
        // message incompréhensible, et la formule est le plus souvent juste ailleurs.
        double v = r.is_number() ? r.as_num() : 0.0;
        samples[i] = (float)(v < -1.0 ? -1.0 : (v > 1.0 ? 1.0 : v));
    }
    return ctx.ret(make_buffer_handle(new_buffer(std::move(samples))));
}

int buf_play(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.play");
    audio_wake();
    sound_output_ensure();
    Buf& b = bufs()[i];
    b.pos = 0.0;   // rejouer repart du début, comme PlaySound
    b.playing.store(true, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int buf_stop(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.stop");
    bufs()[i].playing.store(false, std::memory_order_relaxed);
    bufs()[i].retired_epoch = sound_mix_epoch();
    return ctx.ret(ctx.args[0]);
}

int buf_is_playing(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.isPlaying");
    return ctx.ret(Value::make_bool(bufs()[i].playing.load(std::memory_order_relaxed)));
}

int buf_volume(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.volume");
    double v = sound_check_unit(ctx.args + 1, ctx.argc - 1, 0, "sound.volume", "volume", 0.0);
    if (v < -1.0)
        return ctx.ret(Value(bufs()[i].volume.load(std::memory_order_relaxed)));
    bufs()[i].volume.store(v, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int buf_pan(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.pan");
    double p = sound_check_unit(ctx.args + 1, ctx.argc - 1, 0, "sound.pan", "pan", -1.0);
    if (p < -1.5)
        return ctx.ret(Value(bufs()[i].pan.load(std::memory_order_relaxed)));
    bufs()[i].pan.store(p, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

// `rate` change la vitesse de lecture, donc la hauteur ET la durée — comme un disque qu'on
// accélère. C'est le nom de p5, et il dit bien qu'il ne s'agit pas d'une transposition.
int buf_rate(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.rate");
    if (ctx.argc < 2 || ctx.args[1].is_nil())
        return ctx.ret(Value(bufs()[i].rate.load(std::memory_order_relaxed)));
    if (!ctx.args[1].is_number())
        throw std::runtime_error("sound.rate: rate must be a number");
    double r = ctx.args[1].as_num();
    if (r <= 0.0 || r > 16.0)
        throw std::runtime_error("sound.rate: rate out of ]0;16]");
    bufs()[i].rate.store(r, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int buf_loop(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.loop");
    if (ctx.argc < 2 || ctx.args[1].is_nil()) {
        bufs()[i].loop.store(true, std::memory_order_relaxed);
        return ctx.ret(ctx.args[0]);
    }
    if (!ctx.args[1].is_bool())
        throw std::runtime_error("sound.loop: expected true, false, or no argument");
    bufs()[i].loop.store(ctx.args[1].as_bool(), std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

// ── Accesseurs : ce qui rend la synthèse VÉRIFIABLE ──────────────────────────────
// Sans eux, la seule chose qu'un test puisse contrôler serait les refus : le conteneur
// d'intégration n'a pas de carte son, et personne n'écoute.

int buf_duration(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.duration");
    return ctx.ret(Value((double)bufs()[i].samples.size() / (double)k_audio_sample_rate));
}

int buf_peak(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.peak");
    double crete = 0.0;
    for (float s : bufs()[i].samples) {
        double a = s < 0.0f ? -(double)s : (double)s;
        if (a > crete)
            crete = a;
    }
    return ctx.ret(Value(crete));
}

// Échantillon à l'instant t, en secondes. Hors du tampon : zéro, comme le silence qui
// l'entoure — plutôt qu'une erreur, car un test qui balaie le temps dépasse volontiers la
// fin de quelques microsecondes.
int buf_sample(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.sample");
    if (ctx.argc < 2 || !ctx.args[1].is_number())
        throw std::runtime_error("sound.sample: expected a time in seconds");
    double t = ctx.args[1].as_num();
    const std::vector<float>& d = bufs()[i].samples;
    if (t < 0.0)
        return ctx.ret(Value(0.0));
    size_t idx = (size_t)(t * k_audio_sample_rate);
    if (idx >= d.size())
        return ctx.ret(Value(0.0));
    return ctx.ret(Value((double)d[idx]));
}

// Enveloppe appliquée AUX ÉCHANTILLONS, une fois : un tampon n'a pas de note tenue, donc le
// relâchement se termine exactement à la fin du son. C'est la même fonction que celle du
// mélangeur (sound_env.h), si bien qu'un test sur un tampon valide la courbe des deux.
int buf_envelope(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.envelope");
    sound_check_envelope(ctx.args + 1, ctx.argc - 1, "sound.envelope");
    Adsr e;
    e.attack = ctx.args[1].as_num();
    e.decay = ctx.args[2].as_num();
    e.sustain = ctx.args[3].as_num();
    e.release = ctx.args[4].as_num();
    std::vector<float>& d = bufs()[i].samples;
    double duration = (double)d.size() / (double)k_audio_sample_rate;
    double hold = duration - e.release;
    if (hold < 0.0)
        hold = 0.0;
    for (size_t k = 0; k < d.size(); k++) {
        double t = (double)k / (double)k_audio_sample_rate;
        d[k] = (float)((double)d[k] * adsr_level(e, t, hold));
    }
    return ctx.ret(ctx.args[0]);
}

Value make_buffer_class() {
    Value cls = Value::make_class();
    cls.map_set(Value(std::string("__name__")), Value(std::string("Sound")));
    cls.map_set(Value(std::string("play")), Value::make_builtin(buf_play));
    cls.map_set(Value(std::string("stop")), Value::make_builtin(buf_stop));
    cls.map_set(Value(std::string("isPlaying")), Value::make_builtin(buf_is_playing));
    cls.map_set(Value(std::string("volume")), Value::make_builtin(buf_volume));
    cls.map_set(Value(std::string("pan")), Value::make_builtin(buf_pan));
    cls.map_set(Value(std::string("rate")), Value::make_builtin(buf_rate));
    cls.map_set(Value(std::string("loop")), Value::make_builtin(buf_loop));
    cls.map_set(Value(std::string("duration")), Value::make_builtin(buf_duration));
    cls.map_set(Value(std::string("peak")), Value::make_builtin(buf_peak));
    cls.map_set(Value(std::string("sample")), Value::make_builtin(buf_sample));
    cls.map_set(Value(std::string("envelope")), Value::make_builtin(buf_envelope));
    return cls;
}

Value buffer_class() {
    static Value cls = make_buffer_class();
    return cls;
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
    cls.map_set(Value(std::string("envelope")), Value::make_builtin(method_envelope));
    cls.map_set(Value(std::string("trigger")), Value::make_builtin(method_trigger));
    cls.map_set(Value(std::string("release")), Value::make_builtin(method_release));
    cls.map_set(Value(std::string("free")), Value::make_builtin(method_free));
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

// Drapeau de pause : lu par le mélangeur à chaque bloc, écrit par la session (module audio).
std::atomic<bool>& paused_flag() {
    static std::atomic<bool> paused{false};
    return paused;
}

bool sound_paused() {
    return paused_flag().load(std::memory_order_relaxed);
}

void sound_set_paused(bool paused) {
    paused_flag().store(paused, std::memory_order_relaxed);
}

Buf* sound_buffers() {
    static Buf table[k_max_buffers];
    return table;
}

void sound_reset() {
    sound_set_paused(false);
    // Les tampons sont TUS mais leurs échantillons ne sont pas libérés : un bloc de mélange
    // déjà en cours peut encore les lire, et rien ne presse — le slot sera réutilisé plus
    // tard, une fois qu'un bloc se sera écoulé (cf. alloc_buffer).
    Buf* b = sound_buffers();
    for (int i = 0; i < k_max_buffers; i++) {
        b[i].playing.store(false, std::memory_order_relaxed);
        b[i].used = false;
        b[i].gen++;
        b[i].retired_epoch = sound_mix_epoch();
    }
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
    m.map_set(Value(std::string("note")), Value::make_builtin(sound_note));
    m.map_set(Value(std::string("tone")), Value::make_builtin(sound_tone));
    m.map_set(Value(std::string("generate")), Value::make_builtin(sound_generate));
    return m;
}
