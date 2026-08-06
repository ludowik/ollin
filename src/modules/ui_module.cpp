#include "ui_module.h"
#include "graphics_internal.h"
#include "module_utils.h"
#include "vm.h"
#include <raylib.h>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

// ── Module `ui` — widgets dessinés par le MOTEUR ────────────────────────────────
// Pile ancrée en haut à droite de la zone de tracé. Aucune dépendance au DOM : le
// même code sert en natif, sous Xvfb et dans le playground.
//
//   ui.button("Rejouer", rejouer)
//   ui.checkbox("Grille", ref grille [, surChange])
//   var reglages = ui.menu("Réglages")   -- conteneur ; mêmes méthodes
//   ui.show(reglages)                    -- remplace le menu global affiché
//   ui.back()                            -- remonte d'un niveau
//
// Modèle RETENU : un widget est déclaré UNE fois (au niveau du fichier ou dans
// setup()) ; le moteur le garde, le dessine et le teste à chaque frame. Rien à
// appeler dans draw().
//
// NAVIGATION : un seul menu est affiché à la fois. `s_nav` est la pile courante —
// `s_nav[0]` est le menu global (la racine implicite par défaut), les suivants la
// descente dans les sous-menus. Cliquer un sous-menu empile, la ligne « < » dépile.
//
// Le clic est traité AVANT mouse_poll (cf. ui_poll) : cliquer un widget ne déclenche
// donc pas aussi le mouse.pressed du script.

namespace {

struct Node {
    enum Kind { BUTTON, CHECKBOX, SLIDER, MENU };
    Kind kind = BUTTON;
    std::string label;
    Value action;      // bouton : fonction appelée au clic
    Value target;      // case : référence (`ref x`) vers la variable liée
    Value on_change;   // case/slider : fonction optionnelle appelée après changement
    double vmin = 0.0;     // slider : bornes de la plage
    double vmax = 1.0;
    double vdefault = 0.0; // slider : valeur si la variable liée vaut nil
    bool integral = false; // slider : bornes entières → valeur entière
    std::vector<int> children;   // menu : slots de son contenu, dans l'ordre déclaré
    int parent = -1;
    uint32_t gen = 1;   // incrémentée à la libération → un handle périmé est détecté
    bool alive = false;
    // Géométrie de la dernière frame dessinée, réutilisée par le test de clic pour
    // que la zone cliquable soit EXACTEMENT ce qui est affiché.
    Rectangle box = {0, 0, 0, 0};
};

// Table à identités stables : un handle porte {slot, gen}, jamais un pointeur — le
// vector se réalloue dès qu'un widget est déclaré depuis un callback.
std::vector<Node> s_nodes;
std::vector<int> s_free;
int s_root = -1;
std::vector<int> s_nav;
Rectangle s_back_box = {0, 0, 0, 0};   // ligne de retour de la frame dessinée
// Slider en cours de glissement : le suivi dure plusieurs frames, donc on retient le
// nœud par identité (un slot seul pourrait avoir été recyclé entre deux frames).
int s_drag = -1;
uint32_t s_drag_gen = 0;

bool node_alive(int slot, uint32_t gen) {
    return slot >= 0 && slot < (int)s_nodes.size() && s_nodes[slot].alive && s_nodes[slot].gen == gen;
}

int alloc_node(Node::Kind kind, const std::string& label, int parent) {
    int slot;
    if (!s_free.empty()) {
        slot = s_free.back();
        s_free.pop_back();
    } else {
        s_nodes.push_back(Node{});
        slot = (int)s_nodes.size() - 1;
    }
    Node& n = s_nodes[slot];
    uint32_t gen = n.gen;
    n = Node{};
    n.gen = gen;
    n.alive = true;
    n.kind = kind;
    n.label = label;
    n.parent = parent;
    if (parent >= 0)
        s_nodes[parent].children.push_back(slot);
    return slot;
}

void free_subtree(int slot) {
    std::vector<int> kids = s_nodes[slot].children;
    for (int k : kids)
        free_subtree(k);
    Node& n = s_nodes[slot];
    n.alive = false;
    n.gen++;
    n.action = Value{};
    n.target = Value{};
    n.on_change = Value{};
    n.children.clear();
    n.label.clear();
    // Le slot est recyclable : sans cet effacement, le prochain nœud qui l'occupe
    // hériterait du rectangle du disparu et serait cliquable avant d'être dessiné.
    n.box = {0, 0, 0, 0};
    s_free.push_back(slot);
}

int ui_root() {
    if (s_root < 0 || !s_nodes[s_root].alive)
        s_root = alloc_node(Node::MENU, std::string(), -1);
    return s_root;
}

// La pile ne doit jamais désigner un menu libéré : après une suppression, on la
// tronque au premier ancêtre encore vivant (sinon on afficherait du vide).
void prune_nav() {
    size_t keep = 0;
    while (keep < s_nav.size() && s_nodes[s_nav[keep]].alive)
        keep++;
    s_nav.resize(keep);
    if (s_nav.empty())
        s_nav.push_back(ui_root());
}

int current_menu() {
    if (s_nav.empty())
        s_nav.push_back(ui_root());
    return s_nav.back();
}

// ── Handles côté script : instance de classe native portant {slot, gen} ─────────

int handle_slot(const Value& self, const char* fn) {
    Value slot = self.map_get(Value(std::string("slot")));
    Value gen = self.map_get(Value(std::string("gen")));
    if (!slot.is_integer() || !gen.is_integer())
        throw std::runtime_error(std::string(fn) + ": expected a ui element");
    if (!node_alive((int)slot.as_int(), (uint32_t)gen.as_int()))
        throw std::runtime_error(std::string(fn) + ": this ui element has been removed");
    return (int)slot.as_int();
}

int menu_slot(const Value& self, const char* fn) {
    int slot = handle_slot(self, fn);
    if (s_nodes[slot].kind != Node::MENU)
        throw std::runtime_error(std::string(fn) + ": this ui element is not a menu");
    return slot;
}

Value element_class();

Value make_handle(int slot) {
    Value h = Value::make_map();
    h.map_set(Value(std::string("__class__")), element_class());
    h.map_set(Value(std::string("slot")), Value((int64_t)slot));
    h.map_set(Value(std::string("gen")), Value((int64_t)s_nodes[slot].gen));
    return h;
}

// ── Style ───────────────────────────────────────────────────────────────────────
// TOUTE l'apparence est ici, et NULLE PART ailleurs : couleurs, épaisseurs, et
// proportions. Les tailles sont des FRACTIONS de la hauteur de la zone de tracé
// (comme le joystick) : le canvas est en pixels physiques — sur mobile, plusieurs par
// pixel d'affichage —, donc des tailles fixes donneraient une interface illisible là
// et énorme ailleurs. Changer le style se fait en éditant ce seul bloc : le rendu ne
// lit aucune valeur d'apparence en dur.
struct Style {
    Color bg;
    Color bg_hover;
    Color border;
    Color text;
    Color check;      // remplissage d'une case cochée
    Color chevron;    // marque d'un sous-menu
    Color track;      // fond de la glissière d'un slider
    Color knob;       // partie remplie de la glissière
    float border_thick;
    float font_frac;  // police, fraction de la hauteur de la zone
    float font_min;   // en dessous, illisible quelle que soit la zone
    float pad_frac;   // marge interne, fraction de la police
    float row_frac;   // hauteur d'une ligne
    float slider_row_frac;   // hauteur d'une ligne de slider (libellé + glissière)
    float gap_frac;   // espace entre deux lignes
    float margin_frac;// marge au bord de la zone
    float box_frac;   // côté du carré d'une case
    float check_inset;// retrait du remplissage dans le carré, fraction du carré
    float track_frac; // épaisseur de la glissière
};

const Style STYLE = {
    {40, 44, 54, 220},     // bg
    {58, 64, 78, 235},     // bg_hover
    {120, 130, 150, 255},  // border
    {228, 232, 240, 255},  // text
    {120, 220, 150, 255},  // check
    {150, 160, 180, 255},  // chevron
    {28, 31, 38, 255},     // track
    {96, 168, 232, 255},   // knob
    1.0f,                  // border_thick
    0.026f,                // font_frac
    10.0f,                 // font_min
    0.62f,                 // pad_frac
    1.9f,                  // row_frac
    3.0f,                  // slider_row_frac
    0.38f,                 // gap_frac
    0.75f,                 // margin_frac
    1.0f,                  // box_frac
    0.22f,                 // check_inset
    0.34f,                 // track_frac
};

const char* CHEVRON = ">";
const char* BACK_MARK = "<";

struct Metrics {
    float font;
    float pad;
    float row;
    float slider_row;
    float gap;
    float margin;
    float box;
    float track;
};

Metrics metrics() {
    float h = (float)gfx_logical_height();
    Metrics m;
    m.font = h * STYLE.font_frac;
    if (m.font < STYLE.font_min)
        m.font = STYLE.font_min;
    m.pad = m.font * STYLE.pad_frac;
    m.row = m.font * STYLE.row_frac;
    m.slider_row = m.font * STYLE.slider_row_frac;
    m.gap = m.font * STYLE.gap_frac;
    m.margin = m.font * STYLE.margin_frac;
    m.box = m.font * STYLE.box_frac;
    m.track = m.font * STYLE.track_frac;
    return m;
}

float text_width(const std::string& text, float font_size) {
    Font font = GetFontDefault();
    if (font.texture.id == 0 || font.baseSize == 0)
        return (float)text.size() * font_size * 0.5f;   // sans canvas : estimation
    return MeasureTextEx(font, text.c_str(), font_size, font_size / (float)font.baseSize).x;
}

// Libellé de la ligne de retour : « < » suivi du menu parent (la racine est anonyme).
std::string back_label() {
    if (s_nav.size() < 2)
        return std::string();
    const std::string& parent = s_nodes[s_nav[s_nav.size() - 2]].label;
    return parent.empty() ? std::string(BACK_MARK) : std::string(BACK_MARK) + " " + parent;
}

// ── Slider : la variable liée est la SEULE source de vérité ─────────────────────
// Le nœud ne mémorise pas la valeur courante : elle est lue dans la variable à chaque
// frame, donc le script peut l'écrire lui-même et la glissière suit.
double slider_value(const Value& target, double vmin, double vmax, double vdefault) {
    Value v = ref_get(target);
    double d = v.is_number() ? v.as_num() : vdefault;
    if (d < vmin)
        return vmin;
    if (d > vmax)
        return vmax;
    return d;
}

std::string slider_text(double value, bool integral) {
    char buf[32];
    if (integral)
        snprintf(buf, sizeof(buf), "%lld", (long long)llround(value));
    else
        snprintf(buf, sizeof(buf), "%.2f", value);
    return std::string(buf);
}

// Écrit la valeur si elle a changé, puis notifie. Rien n'est écrit à l'identique :
// sinon un simple survol maintenu appellerait le rappel à chaque frame.
void slider_set(const Value& target, const Value& on_change, double value, bool integral, double current) {
    if (value == current)
        return;
    Value v = integral ? Value((int64_t)llround(value)) : Value(value);
    ref_set(target, v);
    if (on_change.is_callable())
        VM::current()->call_value(const_cast<Value&>(on_change), v);
}

float row_height(Node::Kind kind, const Metrics& m) {
    return kind == Node::SLIDER ? m.slider_row : m.row;
}

// Zone utile de la glissière : c'est elle qui traduit un abscisse en valeur, au rendu
// comme au clic — une seule vérité, donc la poignée est là où l'on croit cliquer.
Rectangle slider_track(const Rectangle& rect, const Metrics& m) {
    return {rect.x + m.pad, rect.y + rect.height - m.pad - m.track, rect.width - 2 * m.pad, m.track};
}

// Largeur commune à toutes les lignes : celle de la plus large, pour une pile alignée.
float stack_width(const Metrics& m, const std::vector<int>& rows) {
    float widest = text_width(back_label(), m.font);
    for (int slot : rows) {
        const Node& n = s_nodes[slot];
        float need = text_width(n.label, m.font);
        if (n.kind == Node::CHECKBOX)
            need += m.box + m.pad;
        if (n.kind == Node::MENU)
            need += m.pad + text_width(CHEVRON, m.font);
        if (n.kind == Node::SLIDER) {
            // Place pour la valeur affichée à droite : la plus large des deux bornes.
            float vw = text_width(slider_text(n.vmin, n.integral), m.font);
            float vmaxw = text_width(slider_text(n.vmax, n.integral), m.font);
            need += m.pad + (vmaxw > vw ? vmaxw : vw);
        }
        if (need > widest)
            widest = need;
    }
    return widest + 2.0f * m.pad;
}

// La cible est prise par COPIE, jamais depuis s_nodes : lire une référence appelle
// un getter du script, qui peut déclarer un widget et réallouer la table.
bool checkbox_state(const Value& target) {
    return !is_falsy(ref_get(target));
}

// Bascule d'une case : écrit la variable liée puis notifie. Même exigence de copie.
void toggle_checkbox(const Value& target, const Value& on_change) {
    Value state = Value(checkbox_state(target) ? int64_t(0) : int64_t(1));
    ref_set(target, state);
    if (on_change.is_callable())
        VM::current()->call_value(const_cast<Value&>(on_change), state);
}

} // namespace

// ── Déclaration de contenu ──────────────────────────────────────────────────────

static int add_button(CallCtx& ctx, const Value* args, int argc, int parent) {
    ui_check_button_args(args, argc);
    int slot = alloc_node(Node::BUTTON, args[0].as_string(), parent);
    s_nodes[slot].action = args[1];
    return ctx.ret(make_handle(slot));
}

static int add_checkbox(CallCtx& ctx, const Value* args, int argc, int parent) {
    ui_check_checkbox_args(args, argc);
    int slot = alloc_node(Node::CHECKBOX, args[0].as_string(), parent);
    s_nodes[slot].target = args[1];
    if (argc > 2)
        s_nodes[slot].on_change = args[2];
    return ctx.ret(make_handle(slot));
}

static int add_slider(CallCtx& ctx, const Value* args, int argc, int parent) {
    ui_check_slider_args(args, argc);
    ui_slider_init(args, argc);
    int slot = alloc_node(Node::SLIDER, args[0].as_string(), parent);
    Node& n = s_nodes[slot];
    n.target = args[1];
    n.vmin = args[2].as_num();
    n.vmax = args[3].as_num();
    n.vdefault = ui_slider_default(args, argc).as_num();
    // Slider ENTIER seulement si les bornes ET la valeur de départ le sont : sinon un
    // slider 0..1 réglant un facteur flottant arrondirait à 0 ou 1.
    n.integral = args[2].is_integer() && args[3].is_integer() && ref_get(args[1]).is_integer();
    for (int i = 4; i < argc; ++i) {
        if (args[i].is_callable())
            n.on_change = args[i];
    }
    return ctx.ret(make_handle(slot));
}

static int add_menu(CallCtx& ctx, const Value* args, int argc, int parent) {
    ui_check_menu_args(args, argc);
    int slot = alloc_node(Node::MENU, args[0].as_string(), parent);
    return ctx.ret(make_handle(slot));
}

static int ui_button(CallCtx& ctx) {
    return add_button(ctx, ctx.args, ctx.argc, ui_root());
}

static int ui_checkbox(CallCtx& ctx) {
    return add_checkbox(ctx, ctx.args, ctx.argc, ui_root());
}

static int ui_slider(CallCtx& ctx) {
    return add_slider(ctx, ctx.args, ctx.argc, ui_root());
}

static int ui_menu(CallCtx& ctx) {
    return add_menu(ctx, ctx.args, ctx.argc, ui_root());
}

// Méthodes d'un menu : le receveur est en args[0], les arguments utilisateur suivent.

static int menu_button(CallCtx& ctx) {
    int parent = menu_slot(ctx.args[0], "menu.button");
    return add_button(ctx, ctx.args + 1, ctx.argc - 1, parent);
}

static int menu_checkbox(CallCtx& ctx) {
    int parent = menu_slot(ctx.args[0], "menu.checkbox");
    return add_checkbox(ctx, ctx.args + 1, ctx.argc - 1, parent);
}

static int menu_slider(CallCtx& ctx) {
    int parent = menu_slot(ctx.args[0], "menu.slider");
    return add_slider(ctx, ctx.args + 1, ctx.argc - 1, parent);
}

static int menu_menu(CallCtx& ctx) {
    int parent = menu_slot(ctx.args[0], "menu.menu");
    return add_menu(ctx, ctx.args + 1, ctx.argc - 1, parent);
}

// ── Navigation ──────────────────────────────────────────────────────────────────

// menu.open() : descend dans ce menu depuis le menu affiché (ce que fait aussi un
// clic sur sa ligne). Empile, donc ui.back() y revient.
static int menu_open(CallCtx& ctx) {
    int slot = menu_slot(ctx.args[0], "menu.open");
    s_nav.push_back(slot);
    return ctx.ret(ctx.args[0]);
}

// ui.show(menu) : remplace le menu global affiché ; la pile de navigation repart de
// zéro (ui.back() n'y remonte donc pas). ui.show(nil) revient au menu racine.
static int ui_show(CallCtx& ctx) {
    int slot;
    if (ctx.argc < 1 || ctx.args[0].is_nil())
        slot = ui_root();
    else
        slot = menu_slot(ctx.args[0], "ui.show");
    s_nav.clear();
    s_nav.push_back(slot);
    return ctx.ret(Value{});
}

// ui.back() : remonte d'un niveau ; sans effet sur le menu global (pile à 1 entrée).
static int ui_back(CallCtx& ctx) {
    if (s_nav.size() > 1)
        s_nav.pop_back();
    return ctx.ret(Value{});
}

static int ui_current(CallCtx& ctx) {
    return ctx.ret(make_handle(current_menu()));
}

// ── Manipulation du contenu ─────────────────────────────────────────────────────

static int element_remove(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "remove");
    if (slot == s_root)
        throw std::runtime_error("remove: the root menu cannot be removed");
    int parent = s_nodes[slot].parent;
    if (parent >= 0) {
        std::vector<int>& kids = s_nodes[parent].children;
        for (size_t i = 0; i < kids.size(); ++i) {
            if (kids[i] == slot) {
                kids.erase(kids.begin() + i);
                break;
            }
        }
    }
    free_subtree(slot);
    prune_nav();
    return ctx.ret(Value{});
}

static int menu_clear(CallCtx& ctx) {
    int slot = menu_slot(ctx.args[0], "menu.clear");
    std::vector<int> kids = s_nodes[slot].children;
    s_nodes[slot].children.clear();
    for (int k : kids)
        free_subtree(k);
    prune_nav();
    return ctx.ret(ctx.args[0]);
}

// ui.clear() : vide TOUT et remet le menu racine (les handles deviennent périmés).
static int ui_clear(CallCtx& ctx) {
    ui_reset();
    return ctx.ret(Value{});
}

namespace {

Value make_element_class() {
    Value cls = Value::make_class();
    cls.map_set(Value(std::string("__name__")), Value(std::string("UiElement")));
    cls.map_set(Value(std::string("button")), Value::make_builtin(menu_button));
    cls.map_set(Value(std::string("checkbox")), Value::make_builtin(menu_checkbox));
    cls.map_set(Value(std::string("slider")), Value::make_builtin(menu_slider));
    cls.map_set(Value(std::string("menu")), Value::make_builtin(menu_menu));
    cls.map_set(Value(std::string("open")), Value::make_builtin(menu_open));
    cls.map_set(Value(std::string("clear")), Value::make_builtin(menu_clear));
    cls.map_set(Value(std::string("remove")), Value::make_builtin(element_remove));
    return cls;
}

Value element_class() {
    static Value cls = make_element_class();
    return cls;
}

} // namespace

// ── Boucle de rendu ────────────────────────────────────────────────────────────

void ui_reset() {
    s_nodes.clear();
    s_free.clear();
    s_nav.clear();
    s_root = -1;
    s_back_box = {0, 0, 0, 0};
    s_drag = -1;
}

namespace {

// Calcule la géométrie des lignes affichées et la mémorise dans chaque nœud. Appelé
// par le rendu ; le test de clic réutilise ces rectangles (une seule vérité).
void layout(const Metrics& m, const std::vector<int>& rows) {
    float w = stack_width(m, rows);
    float x = (float)gfx_logical_width() - m.margin - w;
    // Sous l'overlay FPS, qui occupe le même coin et se compose par-dessus la frame.
    float y = (float)gfx_overlay_height() + m.margin;
    s_back_box = {0, 0, 0, 0};
    if (s_nav.size() > 1) {
        s_back_box = {x, y, w, m.row};
        y += m.row + m.gap;
    }
    for (int slot : rows) {
        float h = row_height(s_nodes[slot].kind, m);
        s_nodes[slot].box = {x, y, w, h};
        y += h + m.gap;
    }
}

void draw_row(const Rectangle& rect, bool hover) {
    DrawRectangleRec(rect, hover ? STYLE.bg_hover : STYLE.bg);
    DrawRectangleLinesEx(rect, STYLE.border_thick, STYLE.border);
}

void draw_text_at(const std::string& text, float x, const Rectangle& rect, const Metrics& m, Color color) {
    Font f = GetFontDefault();
    if (f.texture.id == 0 || f.baseSize == 0)
        return;
    Vector2 pos = {x, rect.y + (rect.height - m.font) * 0.5f};
    DrawTextEx(f, text.c_str(), pos, m.font, m.font / (float)f.baseSize, color);
}

} // namespace

void ui_draw() {
    if (s_nodes.empty())
        return;
    std::vector<int> rows = s_nodes[current_menu()].children;
    if (rows.empty() && s_nav.size() < 2)
        return;
    Metrics m = metrics();
    layout(m, rows);
    Vector2 mouse = {(float)GetMouseX(), (float)GetMouseY()};
    if (s_nav.size() > 1) {
        draw_row(s_back_box, CheckCollisionPointRec(mouse, s_back_box));
        draw_text_at(back_label(), s_back_box.x + m.pad, s_back_box, m, STYLE.text);
    }
    for (int slot : rows) {
        // Copies locales : lire l'état d'une case appelle une closure du script, qui
        // pourrait déclarer un widget et réallouer s_nodes sous nos pieds.
        Rectangle rect = s_nodes[slot].box;
        Node::Kind kind = s_nodes[slot].kind;
        std::string label = s_nodes[slot].label;
        Value target = s_nodes[slot].target;
        bool checked = kind == Node::CHECKBOX && checkbox_state(target);
        draw_row(rect, CheckCollisionPointRec(mouse, rect));
        // Un slider réserve le bas de sa ligne à la glissière : le texte se centre dans
        // la partie qui reste.
        Rectangle text_rect = rect;
        if (kind == Node::SLIDER)
            text_rect.height = rect.height - m.track - m.pad;
        float tx = rect.x + m.pad;
        if (kind == Node::CHECKBOX) {
            Rectangle box = {rect.x + m.pad, rect.y + (m.row - m.box) * 0.5f, m.box, m.box};
            DrawRectangleLinesEx(box, STYLE.border_thick, STYLE.border);
            if (checked) {
                float inset = m.box * STYLE.check_inset;
                Rectangle fill = {box.x + inset, box.y + inset, m.box - 2 * inset, m.box - 2 * inset};
                DrawRectangleRec(fill, STYLE.check);
            }
            tx = box.x + m.box + m.pad;
        }
        if (kind == Node::SLIDER) {
            double vmin = s_nodes[slot].vmin;
            double vmax = s_nodes[slot].vmax;
            double value = slider_value(target, vmin, vmax, s_nodes[slot].vdefault);
            bool integral = s_nodes[slot].integral;
            Rectangle track = slider_track(rect, m);
            DrawRectangleRec(track, STYLE.track);
            float t = (float)((value - vmin) / (vmax - vmin));
            Rectangle filled = {track.x, track.y, track.width * t, track.height};
            DrawRectangleRec(filled, STYLE.knob);
            DrawRectangleLinesEx(track, STYLE.border_thick, STYLE.border);
            std::string vtext = slider_text(value, integral);
            float vw = text_width(vtext, m.font);
            draw_text_at(vtext, rect.x + rect.width - m.pad - vw, text_rect, m, STYLE.text);
        }
        draw_text_at(label, tx, text_rect, m, STYLE.text);
        if (kind == Node::MENU) {
            float cw = text_width(CHEVRON, m.font);
            draw_text_at(CHEVRON, rect.x + rect.width - m.pad - cw, rect, m, STYLE.chevron);
        }
    }
}

namespace {

// Valeur désignée par l'abscisse du curseur sur la glissière d'un slider.
double slider_value_at(int slot, float mouse_x, const Metrics& m) {
    const Node& n = s_nodes[slot];
    Rectangle track = slider_track(n.box, m);
    float t = track.width > 0.0f ? (mouse_x - track.x) / track.width : 0.0f;
    if (t < 0.0f)
        t = 0.0f;
    if (t > 1.0f)
        t = 1.0f;
    return n.vmin + t * (n.vmax - n.vmin);
}

// Glissement en cours : la valeur suit le curseur tant que le bouton est maintenu, et
// le clic reste consommé — sinon relâcher au-dessus de la scène la ferait réagir.
bool poll_drag() {
    if (s_drag < 0)
        return false;
    if (!node_alive(s_drag, s_drag_gen) || !IsMouseButtonDown(MOUSE_BUTTON_LEFT)) {
        s_drag = -1;
        return false;
    }
    int slot = s_drag;
    Metrics m = metrics();
    double wanted = slider_value_at(slot, (float)GetMouseX(), m);
    Value target = s_nodes[slot].target;
    Value on_change = s_nodes[slot].on_change;
    bool integral = s_nodes[slot].integral;
    double current = slider_value(target, s_nodes[slot].vmin, s_nodes[slot].vmax, s_nodes[slot].vdefault);
    slider_set(target, on_change, integral ? (double)llround(wanted) : wanted, integral, current);
    return true;
}

} // namespace

bool ui_poll() {
    if (s_nodes.empty())
        return false;
    if (poll_drag())
        return true;
    if (!IsMouseButtonPressed(MOUSE_BUTTON_LEFT))
        return false;
    Vector2 p = {(float)GetMouseX(), (float)GetMouseY()};
    // Les rectangles viennent de la dernière frame dessinée : ce qu'on voit est ce
    // qu'on clique. Avant la première frame, aucune ligne n'a de boîte → aucun clic.
    if (s_nav.size() > 1 && CheckCollisionPointRec(p, s_back_box)) {
        s_nav.pop_back();
        return true;
    }
    std::vector<int> rows = s_nodes[current_menu()].children;
    for (int slot : rows) {
        if (!CheckCollisionPointRec(p, s_nodes[slot].box))
            continue;
        // COPIER avant d'appeler quoi que ce soit : le callback (ou le setter de la
        // référence) peut déclarer un widget ou appeler ui.clear, donc réallouer
        // s_nodes. Passer un champ par référence laisserait une référence pendante
        // PENDANT l'appel.
        Node::Kind kind = s_nodes[slot].kind;
        Value action = s_nodes[slot].action;
        Value target = s_nodes[slot].target;
        Value on_change = s_nodes[slot].on_change;
        if (kind == Node::BUTTON) {
            if (action.is_callable())
                VM::current()->call_value(action);
        } else if (kind == Node::CHECKBOX) {
            toggle_checkbox(target, on_change);
        } else if (kind == Node::SLIDER) {
            // Le clic positionne tout de suite la valeur, puis le glissement prend le
            // relais jusqu'au relâchement.
            s_drag = slot;
            s_drag_gen = s_nodes[slot].gen;
            poll_drag();
        } else {
            s_nav.push_back(slot);
        }
        return true;   // clic consommé : ne pas le transmettre à mouse.pressed
    }
    return false;
}

Value make_ui_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("button")), Value::make_builtin(ui_button));
    m.map_set(Value(std::string("checkbox")), Value::make_builtin(ui_checkbox));
    m.map_set(Value(std::string("slider")), Value::make_builtin(ui_slider));
    m.map_set(Value(std::string("menu")), Value::make_builtin(ui_menu));
    m.map_set(Value(std::string("show")), Value::make_builtin(ui_show));
    m.map_set(Value(std::string("back")), Value::make_builtin(ui_back));
    m.map_set(Value(std::string("current")), Value::make_builtin(ui_current));
    m.map_set(Value(std::string("clear")), Value::make_builtin(ui_clear));
    return m;
}
