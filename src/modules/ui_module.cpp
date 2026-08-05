#include "ui_module.h"
#include "graphics_internal.h"
#include "module_utils.h"
#include "vm.h"
#include <raylib.h>
#include <string>
#include <vector>

// ── Module `ui` — widgets dessinés par le MOTEUR ────────────────────────────────
// Pile ancrée en haut à droite de la zone de tracé. Aucune dépendance au DOM : le
// même code sert en natif, sous Xvfb et dans le playground.
//
//   ui.button("Rejouer", rejouer)
//   ui.checkbox("Grille", ref grille [, surChange])
//
// Modèle RETENU : un widget est déclaré UNE fois (au niveau du fichier ou dans
// setup()) ; le moteur le garde, le dessine et le teste à chaque frame. Rien à
// appeler dans draw().
//
// Le clic est traité AVANT mouse_poll (cf. ui_poll) : cliquer un widget ne déclenche
// donc pas aussi le mouse.pressed du script.

namespace {

struct Widget {
    enum Kind { BUTTON, CHECKBOX };
    Kind kind = BUTTON;
    std::string label;
    Value action;      // bouton : fonction appelée au clic
    Value target;      // case : référence (`ref x`) vers la variable liée
    Value on_change;   // case : fonction optionnelle appelée après changement
    // Géométrie de la dernière frame dessinée, réutilisée par le test de clic pour
    // que la zone cliquable soit EXACTEMENT ce qui est affiché.
    Rectangle box = {0, 0, 0, 0};
};

std::vector<Widget> s_widgets;

// Mise en page PROPORTIONNELLE à la hauteur de la zone de tracé, comme le joystick :
// le canvas est en pixels PHYSIQUES (sur mobile, plusieurs par pixel CSS), donc des
// tailles fixes donneraient une interface illisible là et énorme ailleurs. Un ratio
// s'adapte partout sans avoir à interroger la densité de l'écran.
const float FONT_FRAC = 0.026f;   // taille de police, fraction de la hauteur
const float FONT_MIN = 10.0f;     // en dessous, illisible quelle que soit la zone

const Color C_BG = {40, 44, 54, 220};
const Color C_BG_HOVER = {58, 64, 78, 235};
const Color C_BORDER = {120, 130, 150, 255};
const Color C_TEXT = {228, 232, 240, 255};
const Color C_CHECK = {120, 220, 150, 255};

// Métriques dérivées de la police : une seule source pour le rendu et le test de clic.
struct Metrics {
    float font;
    float pad;
    float row;
    float gap;
    float margin;
    float box;
};

Metrics metrics() {
    float h = (float)gfx_logical_height();
    Metrics m;
    m.font = h * FONT_FRAC;
    if (m.font < FONT_MIN)
        m.font = FONT_MIN;
    m.pad = m.font * 0.62f;
    m.row = m.font * 1.9f;
    m.gap = m.font * 0.38f;
    m.margin = m.font * 0.75f;
    m.box = m.font;
    return m;
}

float text_width(const std::string& text, float font_size) {
    Font font = GetFontDefault();
    if (font.texture.id == 0 || font.baseSize == 0)
        return (float)text.size() * font_size * 0.5f;   // sans canvas : estimation
    return MeasureTextEx(font, text.c_str(), font_size, font_size / (float)font.baseSize).x;
}

// Largeur commune à tous les widgets : celle du plus large, pour une pile alignée.
float stack_width(const Metrics& m) {
    float widest = 0.0f;
    for (auto& w : s_widgets) {
        float need = text_width(w.label, m.font);
        if (w.kind == Widget::CHECKBOX)
            need += m.box + m.pad;
        if (need > widest)
            widest = need;
    }
    return widest + 2.0f * m.pad;
}

bool checkbox_state(const Widget& w) {
    return !is_falsy(ref_get(w.target));
}

} // namespace

// ── ui.button(label, action) ────────────────────────────────────────────────────

static int ui_button(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    ui_check_button_args(args, argc);
    Widget w;
    w.kind = Widget::BUTTON;
    w.label = args[0].as_string();
    w.action = args[1];
    s_widgets.push_back(w);
    return ctx.ret(Value{});
}

// ── ui.checkbox(label, ref cible [, surChange]) ─────────────────────────────────

static int ui_checkbox(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    ui_check_checkbox_args(args, argc);
    Widget w;
    w.kind = Widget::CHECKBOX;
    w.label = args[0].as_string();
    w.target = args[1];
    if (argc > 2)
        w.on_change = args[2];
    s_widgets.push_back(w);
    return ctx.ret(Value{});
}

// ── ui.clear() : retire tous les widgets ───────────────────────────────────────

static int ui_clear(CallCtx& ctx) {
    s_widgets.clear();
    return ctx.ret(Value{});
}

// ── Boucle de rendu ────────────────────────────────────────────────────────────

void ui_reset() {
    s_widgets.clear();
}

// Calcule la géométrie de la pile et la mémorise dans chaque widget. Appelé par le
// rendu ; le test de clic réutilise ces rectangles (une seule vérité géométrique).
static void layout(const Metrics& m) {
    float w = stack_width(m);
    float x = (float)gfx_logical_width() - m.margin - w;
    // Sous l'overlay FPS, qui occupe le même coin et se compose par-dessus la frame.
    float y = (float)gfx_overlay_height() + m.margin;
    for (auto& widget : s_widgets) {
        widget.box = {x, y, w, m.row};
        y += m.row + m.gap;
    }
}

void ui_draw() {
    if (s_widgets.empty())
        return;
    Metrics m = metrics();
    layout(m);
    Vector2 mouse = {(float)GetMouseX(), (float)GetMouseY()};
    Font f = GetFontDefault();
    bool has_font = f.texture.id != 0 && f.baseSize != 0;
    for (auto& w : s_widgets) {
        bool hover = CheckCollisionPointRec(mouse, w.box);
        DrawRectangleRec(w.box, hover ? C_BG_HOVER : C_BG);
        DrawRectangleLinesEx(w.box, 1.0f, C_BORDER);
        float tx = w.box.x + m.pad;
        if (w.kind == Widget::CHECKBOX) {
            Rectangle box = {w.box.x + m.pad, w.box.y + (m.row - m.box) * 0.5f, m.box, m.box};
            DrawRectangleLinesEx(box, 1.0f, C_BORDER);
            if (checkbox_state(w)) {
                float inset = m.box * 0.22f;
                Rectangle fill = {box.x + inset, box.y + inset, m.box - 2 * inset, m.box - 2 * inset};
                DrawRectangleRec(fill, C_CHECK);
            }
            tx = box.x + m.box + m.pad * 0.6f;
        }
        if (has_font) {
            Vector2 pos = {tx, w.box.y + (m.row - m.font) * 0.5f};
            DrawTextEx(f, w.label.c_str(), pos, m.font, m.font / (float)f.baseSize, C_TEXT);
        }
    }
}

bool ui_poll() {
    if (s_widgets.empty())
        return false;
    if (!IsMouseButtonPressed(MOUSE_BUTTON_LEFT))
        return false;
    Vector2 p = {(float)GetMouseX(), (float)GetMouseY()};
    // Les rectangles viennent de la dernière frame dessinée : ce qu'on voit est ce
    // qu'on clique. Avant la première frame, aucun widget n'a de boîte → aucun clic.
    for (auto& w : s_widgets) {
        if (!CheckCollisionPointRec(p, w.box))
            continue;
        VM* vm = VM::current();
        if (w.kind == Widget::BUTTON) {
            if (w.action.is_callable())
                vm->call_value(w.action);
        } else {
            bool now = !checkbox_state(w);
            ref_set(w.target, Value(now ? int64_t(1) : int64_t(0)));
            if (w.on_change.is_callable())
                vm->call_value(w.on_change, Value(now ? int64_t(1) : int64_t(0)));
        }
        return true;   // clic consommé : ne pas le transmettre à mouse.pressed
    }
    return false;
}

Value make_ui_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("button")), Value::make_builtin(ui_button));
    m.map_set(Value(std::string("checkbox")), Value::make_builtin(ui_checkbox));
    m.map_set(Value(std::string("clear")), Value::make_builtin(ui_clear));
    return m;
}
