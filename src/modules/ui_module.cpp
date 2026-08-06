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
    enum Kind { BUTTON, CHECKBOX, MENU };
    Kind kind = BUTTON;
    std::string label;
    Value action;      // bouton : fonction appelée au clic
    Value target;      // case : référence (`ref x`) vers la variable liée
    Value on_change;   // case : fonction optionnelle appelée après changement
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

// ── Mise en page ────────────────────────────────────────────────────────────────
// PROPORTIONNELLE à la hauteur de la zone de tracé, comme le joystick : le canvas
// est en pixels PHYSIQUES (sur mobile, plusieurs par pixel CSS), donc des tailles
// fixes donneraient une interface illisible là et énorme ailleurs.
const float FONT_FRAC = 0.026f;   // taille de police, fraction de la hauteur
const float FONT_MIN = 10.0f;     // en dessous, illisible quelle que soit la zone

const Color C_BG = {40, 44, 54, 220};
const Color C_BG_HOVER = {58, 64, 78, 235};
const Color C_BORDER = {120, 130, 150, 255};
const Color C_TEXT = {228, 232, 240, 255};
const Color C_CHECK = {120, 220, 150, 255};
const Color C_CHEVRON = {150, 160, 180, 255};

const char* CHEVRON = ">";
const char* BACK_MARK = "<";

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

// Libellé de la ligne de retour : « < » suivi du menu parent (la racine est anonyme).
std::string back_label() {
    if (s_nav.size() < 2)
        return std::string();
    const std::string& parent = s_nodes[s_nav[s_nav.size() - 2]].label;
    return parent.empty() ? std::string(BACK_MARK) : std::string(BACK_MARK) + " " + parent;
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
        s_nodes[slot].box = {x, y, w, m.row};
        y += m.row + m.gap;
    }
}

void draw_row(const Rectangle& rect, bool hover) {
    DrawRectangleRec(rect, hover ? C_BG_HOVER : C_BG);
    DrawRectangleLinesEx(rect, 1.0f, C_BORDER);
}

void draw_text_at(const std::string& text, float x, const Rectangle& rect, const Metrics& m, Color color) {
    Font f = GetFontDefault();
    if (f.texture.id == 0 || f.baseSize == 0)
        return;
    Vector2 pos = {x, rect.y + (m.row - m.font) * 0.5f};
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
        draw_text_at(back_label(), s_back_box.x + m.pad, s_back_box, m, C_TEXT);
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
        float tx = rect.x + m.pad;
        if (kind == Node::CHECKBOX) {
            Rectangle box = {rect.x + m.pad, rect.y + (m.row - m.box) * 0.5f, m.box, m.box};
            DrawRectangleLinesEx(box, 1.0f, C_BORDER);
            if (checked) {
                float inset = m.box * 0.22f;
                Rectangle fill = {box.x + inset, box.y + inset, m.box - 2 * inset, m.box - 2 * inset};
                DrawRectangleRec(fill, C_CHECK);
            }
            tx = box.x + m.box + m.pad * 0.6f;
        }
        draw_text_at(label, tx, rect, m, C_TEXT);
        if (kind == Node::MENU) {
            float cw = text_width(CHEVRON, m.font);
            draw_text_at(CHEVRON, rect.x + rect.width - m.pad - cw, rect, m, C_CHEVRON);
        }
    }
}

bool ui_poll() {
    if (s_nodes.empty())
        return false;
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
    m.map_set(Value(std::string("menu")), Value::make_builtin(ui_menu));
    m.map_set(Value(std::string("show")), Value::make_builtin(ui_show));
    m.map_set(Value(std::string("back")), Value::make_builtin(ui_back));
    m.map_set(Value(std::string("current")), Value::make_builtin(ui_current));
    m.map_set(Value(std::string("clear")), Value::make_builtin(ui_clear));
    return m;
}
