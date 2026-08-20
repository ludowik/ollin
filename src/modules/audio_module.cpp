#include "audio_module.h"
#include "module_utils.h"
#include "sound_internal.h"
#include "raylib.h"
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// Session sonore, build AVEC raylib. Le périphérique n'est PAS ouvert au chargement du
// module : le navigateur refuse de sonner avant une interaction, et ouvrir trop tôt
// donnerait un contexte suspendu dont on ne saurait plus quoi faire. L'ouverture est donc
// différée jusqu'au premier geste de l'utilisateur (audio_wake) ou à un appel explicite
// d'audio.start().

namespace {

bool s_ready = false;
bool s_tried = false;     // une tentative a déjà eu lieu → ne pas la refaire à chaque frame
double s_volume = 1.0;

#ifdef __EMSCRIPTEN__
// Un contexte audio SUSPENDU ne se reprend que depuis le gestionnaire du geste lui-même.
// C'est la règle de Safari sur iOS, et elle condamne notre réveil : `audio_wake` part de la
// boucle de rendu, donc hors de la pile d'appels du geste, et son `resume` est refusé — pour
// toujours. Le son était alors mort jusqu'à la fermeture de l'onglet (MESURÉ : contexte
// suspendu de force, puis trois gestes de plus sans aucun retour du son).
//
// Safari suspend de lui-même sur une interruption (appel entrant, retour d'arrière-plan,
// verrouillage), et le contexte naît suspendu quand il est créé avant tout geste. D'où un
// écouteur DOM, posé UNE fois et gardé : chaque geste retente la reprise, ce qui couvre les
// deux cas sans que le moteur ait à savoir lequel s'est produit.
void install_gesture_resume() {
    static bool pose = false;
    if (pose)
        return;
    pose = true;
    EM_ASM({
        if (window.__ollinAudioResume)
            return;
        window.__ollinAudioResume = 1;
        var reprendre = function() {
            var ma = window.miniaudio;
            if (!ma || !ma.devices)
                return;
            for (var i = 0; i < ma.devices.length; i++) {
                var d = ma.devices[i];
                if (d && d.webaudio && d.webaudio.state !== 'running' && d.webaudio.resume)
                    d.webaudio.resume();
            }
        };
        // Pas de littéral de tableau ni d'objet ici : EM_ASM est une MACRO, et une virgule
        // hors parenthèses y sépare ses arguments.
        var opt = { capture: true };
        opt.passive = true;
        var noms = 'pointerdown touchstart touchend mousedown keydown'.split(' ');
        for (var i = 0; i < noms.length; i++)
            document.addEventListener(noms[i], reprendre, opt);
    });
}
#else
void install_gesture_resume() {
}
#endif

// Ouvre le périphérique une seule fois. L'échec n'est pas une erreur de script : une
// machine sans carte son (conteneur d'intégration, serveur) doit exécuter le programme
// jusqu'au bout, en silence.
bool audio_open() {
    if (s_ready)
        return true;
    if (s_tried)
        return false;
    s_tried = true;
    InitAudioDevice();
    s_ready = IsAudioDeviceReady();
    if (s_ready)
        SetMasterVolume((float)s_volume);
    return s_ready;
}

int audio_start(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(audio_open()));
}

int audio_is_ready(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(s_ready));
}

// Sans argument : rend le volume courant. Avec : le pose et le rend, pour se chaîner.
int audio_volume(CallCtx& ctx) {
    audio_check_volume_args(ctx.args, ctx.argc);
    if (ctx.argc >= 1 && ctx.args[0].is_number()) {
        s_volume = audio_clamp_volume(ctx.args[0].as_num());
        if (s_ready)
            SetMasterVolume((float)s_volume);
    }
    return ctx.ret(Value(s_volume));
}

int audio_sample_rate(CallCtx& ctx) {
    return ctx.ret(Value((int64_t)k_audio_sample_rate));
}

// La pause appartient à la SESSION et non à chaque son : c'est l'équivalent sonore de la
// pause d'une boucle de rendu. Elle suspend l'avancement, là où un volume à zéro laisserait
// tout courir en silence et ferait reprendre le son plus loin qu'on l'a laissé.
int audio_pause(CallCtx& ctx) {
    sound_set_paused(true);
    return ctx.ret(Value{});
}

int audio_resume(CallCtx& ctx) {
    sound_set_paused(false);
    return ctx.ret(Value{});
}

int audio_is_paused(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(sound_paused()));
}

} // namespace

void audio_wake() {
    audio_open();
}

void audio_update() {
}

// Le périphérique, lui, N'EST PAS refermé : il appartient à la page (WASM) et sa fermeture
// invaliderait les tampons encore référencés. Seul l'état propre au programme est remis à
// zéro — le volume, qu'un script précédent a pu baisser.
void audio_reset() {
    // L'écouteur de reprise doit être en place AVANT le premier geste, donc au démarrage du
    // programme et non à l'ouverture du périphérique — celle-ci n'a lieu qu'après un geste,
    // qui serait déjà perdu.
    install_gesture_resume();
    s_volume = 1.0;
    if (s_ready)
        SetMasterVolume(1.0f);
}

Value make_audio_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("start")), Value::make_builtin(audio_start));
    m.map_set(Value(std::string("isReady")), Value::make_builtin(audio_is_ready));
    m.map_set(Value(std::string("volume")), Value::make_builtin(audio_volume));
    m.map_set(Value(std::string("pause")), Value::make_builtin(audio_pause));
    m.map_set(Value(std::string("resume")), Value::make_builtin(audio_resume));
    m.map_set(Value(std::string("isPaused")), Value::make_builtin(audio_is_paused));
    m.map_set(Value(std::string("sampleRate")), Value::make_builtin(audio_sample_rate));
    return m;
}
