#include "ui_module.h"
#include "graphics_internal.h"
#include "module_utils.h"
#include "vm.h"
#include <raylib.h>
#include "engine_font.h"
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
// OUVERTURE : au démarrage l'interface est FERMÉE — une simple poignée à trois barres
// dans le coin. Un clic dessus déplie le menu affiché, dont la ligne de tête porte la
// poignée et le titre ; un clic sur cette tête referme. Côté script : ui.open([menu]),
// ui.close(), ui.toggle() ; ui.show(menu) déplie aussi (montrer = rendre visible).
//
// NAVIGATION : un seul menu est affiché à la fois. `s_nav` est la pile courante —
// `s_nav[0]` est le menu global (la racine implicite par défaut), les suivants la
// descente dans les sous-menus. Cliquer un sous-menu empile, la ligne « < » dépile.
//
// Le clic est traité AVANT mouse_poll (cf. ui_poll) : cliquer un widget ne déclenche
// donc pas aussi le mouse.pressed du script.

namespace {

struct Node {
    // LIST = la ligne « libellé : sélection » ; LIST_ITEM = une ligne de la liste ouverte,
    // engendrée à l'ouverture comme enfant du nœud LIST (donc affichée et cliquée par le
    // mécanisme de menu déjà en place, sans notion de ligne « virtuelle »).
    enum Kind { BUTTON, CHECKBOX, SLIDER, MENU, LIST, LIST_ITEM };
    Kind kind = BUTTON;
    std::string label;
    Value action;      // bouton : fonction appelée au clic
    Value target;      // case : référence (`ref x`) vers la variable liée
    Value on_change;   // case/slider : fonction optionnelle appelée après changement
    double vmin = 0.0;     // slider : bornes de la plage
    double vmax = 1.0;
    double vdefault = 0.0; // slider : valeur si la variable liée vaut nil
    bool integral = false; // slider : bornes entières → valeur entière
    Value source;      // liste : tableau, map ou enum d'où viennent les éléments
    Value item;        // élément de liste : la valeur (ou la clé) renvoyée par la sélection
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
// L'interface est FERMÉE au démarrage : elle se réduit à une poignée dans le coin, pour
// ne pas masquer la scène d'un programme qui ne s'en sert qu'occasionnellement.
bool s_open = false;
Rectangle s_head_box = {0, 0, 0, 0};   // poignée fermée, ou ligne de tête ouverte
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

void open_list(int slot);

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
    Color border;     // contour discret des cases et de la glissière
    Color text;
    Color text_dim;   // valeur d'un slider, chevron d'un sous-menu
    Color accent;     // case cochée, partie remplie d'une glissière
    Color track;      // fond de la glissière d'un slider
    float round;      // arrondi des lignes, 0 = angles droits
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
    float bar_thick_frac;  // épaisseur d'une barre de la poignée, fraction du carré
    float bar_gap_frac;    // écart entre deux barres (0.124 × 21,6 ≈ 2 px de séparation
                           // pour une zone de 600 px de haut ; cf. metrics)
    float bar_width_frac;  // largeur des barres, fraction du carré
};

const Style STYLE = {
    {46, 51, 63, 238},     // bg
    {64, 71, 86, 248},     // bg_hover
    {96, 104, 122, 255},   // border
    {232, 235, 242, 255},  // text
    {148, 156, 174, 255},  // text_dim
    {94, 162, 255, 255},   // accent
    {14, 15, 19, 255},     // track
    0.34f,                 // round
    1.0f,                  // border_thick
    0.020f,                // font_frac
    9.0f,                  // font_min
    0.72f,                 // pad_frac
    1.8f,                  // row_frac
    2.45f,                 // slider_row_frac
    0.22f,                 // gap_frac
    0.9f,                  // margin_frac
    1.45f,                 // box_frac
    0.26f,                 // check_inset
    0.26f,                 // track_frac
    0.105f,                // bar_thick_frac
    0.124f,                // bar_gap_frac
    0.5f,                  // bar_width_frac
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

// Les widgets s'écrivent toujours avec la police par défaut du moteur, indépendamment
// de celle que le script a choisie pour ses propres tracés : l'interface garde son
// apparence quoi que fasse le programme.
Font ui_font() {
    return engine_font(engine_font_default());
}

float text_width(const std::string& text, float font_size) {
    Font font = ui_font();
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

// Écrit la valeur si elle a changé, puis notifie. La comparaison porte sur le contenu
// BRUT de la variable, jamais sur la valeur ramenée aux bornes : sinon une variable
// hors plage (20 pour un slider 1..10) resterait telle quelle, le glissement sur la
// butée n'écrivant jamais. Rien n'est écrit à l'identique, sans quoi un maintien
// immobile appellerait le rappel à chaque frame.
void slider_set(const Value& target, const Value& on_change, double value, bool integral) {
    Value current = ref_get(target);
    if (current.is_number() && current.as_num() == value)
        return;
    Value v = integral ? Value((int64_t)llround(value)) : Value(value);
    ref_set(target, v);
    if (on_change.is_callable())
        VM::current()->call_value(const_cast<Value&>(on_change), v);
}

// Libellé de l'élément retenu par une liste. La cible est passée par COPIE (lire une
// référence exécute un getter du script, qui peut réallouer s_nodes).
std::string list_text(const Value& target) {
    Value cur = ref_get(target);
    return cur.is_nil() ? std::string("—") : value_to_string(cur);
}

// Égalité des valeurs du langage (celle des clés de map) : un entier et un flottant de
// même valeur sont identiques, les chaînes se comparent par pointeur interné.
bool same_item(const Value& a, const Value& b) {
    return ValueEqual{}(a, b);
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
    // Ligne de tête : poignée + titre du menu affiché.
    float head = m.row + text_width(s_nodes[current_menu()].label, m.font);
    if (head > widest)
        widest = head;
    for (int slot : rows) {
        // Champs COPIÉS, aucune référence sur le nœud : la largeur d'une liste demande la
        // valeur retenue, dont la lecture exécute un getter du script — lequel peut
        // déclarer un widget et réallouer s_nodes.
        Node::Kind kind = s_nodes[slot].kind;
        float need = text_width(s_nodes[slot].label, m.font);
        if (kind == Node::CHECKBOX || kind == Node::LIST_ITEM)
            need += m.box + m.pad;   // case à cocher, ou marque de l'élément retenu
        if (kind == Node::MENU)
            need += m.pad + text_width(CHEVRON, m.font);
        if (kind == Node::SLIDER) {
            // Place pour la valeur affichée à droite : la plus large des deux bornes.
            bool integral = s_nodes[slot].integral;
            float vw = text_width(slider_text(s_nodes[slot].vmin, integral), m.font);
            float vmaxw = text_width(slider_text(s_nodes[slot].vmax, integral), m.font);
            need += m.pad + (vmaxw > vw ? vmaxw : vw);
        }
        if (kind == Node::LIST) {
            Value target = s_nodes[slot].target;
            need += m.pad + text_width(list_text(target), m.font);
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
    // TOUT ce qui appelle le script — ici la lecture de la référence — est fait AVANT
    // d'allouer le nœud : un getter peut déclarer un widget, donc réallouer s_nodes, et
    // la référence `n` obtenue avant l'appel désignerait alors de la mémoire libérée.
    // Slider ENTIER seulement si les bornes ET la valeur de départ le sont : sinon un
    // slider 0..1 réglant un facteur flottant arrondirait à 0 ou 1.
    bool integral = args[2].is_integer() && args[3].is_integer() && ref_get(args[1]).is_integer();
    int slot = alloc_node(Node::SLIDER, args[0].as_string(), parent);
    Node& n = s_nodes[slot];
    n.target = args[1];
    n.vmin = args[2].as_num();
    n.vmax = args[3].as_num();
    n.vdefault = ui_slider_default(args, argc).as_num();
    n.integral = integral;
    for (int i = 4; i < argc; ++i) {
        if (args[i].is_callable())
            n.on_change = args[i];
    }
    return ctx.ret(make_handle(slot));
}

// La liste est MONO-sélection : la ligne montre l'élément retenu, et un clic ouvre la
// liste (mécanisme des sous-menus) pour en choisir un autre. Les éléments ne sont PAS
// engendrés ici : ils le sont à l'ouverture, donc la liste suit les changements de sa
// source sans rien recalculer par frame.
static int add_list(CallCtx& ctx, const Value* args, int argc, int parent) {
    ui_check_list_args(args, argc);
    ui_list_init(args);   // appelle le script (getter/setter) → AVANT d'allouer le nœud
    int slot = alloc_node(Node::LIST, args[0].as_string(), parent);
    s_nodes[slot].source = args[1];
    s_nodes[slot].target = args[2];
    if (argc > 3)
        s_nodes[slot].on_change = args[3];
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

static int ui_list(CallCtx& ctx) {
    return add_list(ctx, ctx.args, ctx.argc, ui_root());
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

static int menu_list(CallCtx& ctx) {
    int parent = menu_slot(ctx.args[0], "menu.list");
    return add_list(ctx, ctx.args + 1, ctx.argc - 1, parent);
}

static int menu_menu(CallCtx& ctx) {
    int parent = menu_slot(ctx.args[0], "menu.menu");
    return add_menu(ctx, ctx.args + 1, ctx.argc - 1, parent);
}

// ── Navigation ──────────────────────────────────────────────────────────────────

// element.open() : déplie ce menu — ou cette liste — depuis le menu affiché, ce que fait
// aussi un clic sur sa ligne. Empile, donc ui.back() revient en arrière.
static int menu_open(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "menu.open");
    Node::Kind kind = s_nodes[slot].kind;
    if (kind == Node::LIST) {
        open_list(slot);
    } else if (kind == Node::MENU) {
        s_nav.push_back(slot);
    } else {
        throw std::runtime_error("menu.open: this ui element is neither a menu nor a list");
    }
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
    s_open = true;   // « montrer » implique déplier
    return ctx.ret(Value{});
}

// ui.open([menu]) : déplie l'interface, sur le menu donné le cas échéant.
static int ui_open(CallCtx& ctx) {
    if (ctx.argc > 0 && !ctx.args[0].is_nil()) {
        int slot = menu_slot(ctx.args[0], "ui.open");
        s_nav.clear();
        s_nav.push_back(slot);
    }
    s_open = true;
    return ctx.ret(Value{});
}

// ui.close() : replie l'interface sur sa poignée, sans changer le menu affiché.
static int ui_close(CallCtx& ctx) {
    s_open = false;
    return ctx.ret(Value{});
}

static int ui_toggle(CallCtx& ctx) {
    s_open = !s_open;
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
    cls.map_set(Value(std::string("list")), Value::make_builtin(menu_list));
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
    s_head_box = {0, 0, 0, 0};
    s_open = false;
    s_drag = -1;
}

namespace {

// Calcule la géométrie des lignes affichées et la mémorise dans chaque nœud. Appelé
// par le rendu ; le test de clic réutilise ces rectangles (une seule vérité).
void layout(const Metrics& m, const std::vector<int>& rows) {
    float right = (float)gfx_logical_width() - m.margin;
    float y = m.margin;
    s_back_box = {0, 0, 0, 0};
    if (!s_open) {
        s_head_box = {right - m.row, y, m.row, m.row};
        return;
    }
    float w = stack_width(m, rows);
    float x = right - w;
    s_head_box = {x, y, w, m.row};
    y += m.row + m.gap;
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
    DrawRectangleRounded(rect, STYLE.round, 8, hover ? STYLE.bg_hover : STYLE.bg);
}

// Trois barres dessinées à la main : la police par défaut n'a pas de glyphe de menu,
// et un tracé suit le style sans dépendre du jeu de caractères.
void draw_handle(const Rectangle& rect, const Metrics& m) {
    float side = m.row;
    float thick = side * STYLE.bar_thick_frac;
    float gap = side * STYLE.bar_gap_frac;
    float bw = side * STYLE.bar_width_frac;
    float cx = rect.x + (side - bw) * 0.5f;
    float cy = rect.y + (rect.height - (3 * thick + 2 * gap)) * 0.5f;
    for (int i = 0; i < 3; ++i) {
        DrawRectangleRec({cx, cy + i * (thick + gap), bw, thick}, STYLE.text);
    }
}

void draw_text_at(const std::string& text, float x, const Rectangle& rect, const Metrics& m, Color color) {
    Font f = ui_font();
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
    if (rows.empty() && s_nav.size() < 2) {
        // Interface vide : même pas de poignée, et surtout aucune zone cliquable
        // résiduelle (le test de clic lit ces rectangles).
        s_head_box = {0, 0, 0, 0};
        s_back_box = {0, 0, 0, 0};
        return;
    }
    Metrics m = metrics();
    layout(m, rows);
    Vector2 mouse = {(float)GetMouseX(), (float)GetMouseY()};
    draw_row(s_head_box, CheckCollisionPointRec(mouse, s_head_box));
    draw_handle(s_head_box, m);
    if (s_open && !s_nodes[current_menu()].label.empty()) {
        // Le titre du menu affiché n'a de sens qu'ouvert : fermée, la pile se réduit
        // à la poignée.
        std::string title = s_nodes[current_menu()].label;
        draw_text_at(title, s_head_box.x + m.row, s_head_box, m, STYLE.text);
    }
    if (!s_open)
        return;
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
        if (kind == Node::LIST_ITEM) {
            // Marque ronde de l'élément retenu (bouton radio) : la mono-sélection se lit
            // d'un coup d'œil, et la forme la distingue de la case à cocher carrée.
            Value item = s_nodes[slot].item;
            Value target = s_nodes[s_nodes[slot].parent].target;
            bool picked = same_item(item, ref_get(target));
            float r = m.box * 0.5f;
            Vector2 c = {rect.x + m.pad + r, rect.y + m.row * 0.5f};
            DrawCircleLinesV(c, r, STYLE.border);
            if (picked)
                DrawCircleV(c, r * (1.0f - STYLE.check_inset * 2.0f), STYLE.accent);
            tx = rect.x + m.pad + m.box + m.pad;
        }
        if (kind == Node::LIST) {
            std::string vtext = list_text(target);
            float vw = text_width(vtext, m.font);
            draw_text_at(vtext, rect.x + rect.width - m.pad - vw, rect, m, STYLE.text_dim);
        }
        if (kind == Node::CHECKBOX) {
            Rectangle box = {rect.x + m.pad, rect.y + (m.row - m.box) * 0.5f, m.box, m.box};
            DrawRectangleRoundedLinesEx(box, STYLE.round, 6, STYLE.border_thick, STYLE.border);
            if (checked) {
                float inset = m.box * STYLE.check_inset;
                Rectangle fill = {box.x + inset, box.y + inset, m.box - 2 * inset, m.box - 2 * inset};
                DrawRectangleRounded(fill, STYLE.round, 6, STYLE.accent);
            }
            tx = box.x + m.box + m.pad;
        }
        if (kind == Node::SLIDER) {
            double vmin = s_nodes[slot].vmin;
            double vmax = s_nodes[slot].vmax;
            double value = slider_value(target, vmin, vmax, s_nodes[slot].vdefault);
            bool integral = s_nodes[slot].integral;
            Rectangle track = slider_track(rect, m);
            DrawRectangleRounded(track, 1.0f, 6, STYLE.track);
            float t = (float)((value - vmin) / (vmax - vmin));
            // Un remplissage plus court que son arrondi dégénérerait : on n'en dessine
            // que la partie utile, et jamais moins que l'épaisseur du rail.
            if (t > 0.0f) {
                float fw = track.width * t;
                if (fw < track.height)
                    fw = track.height;
                DrawRectangleRounded({track.x, track.y, fw, track.height}, 1.0f, 6, STYLE.accent);
            }
            std::string vtext = slider_text(value, integral);
            float vw = text_width(vtext, m.font);
            draw_text_at(vtext, rect.x + rect.width - m.pad - vw, text_rect, m, STYLE.text_dim);
        }
        draw_text_at(label, tx, text_rect, m, STYLE.text);
        if (kind == Node::MENU) {
            float cw = text_width(CHEVRON, m.font);
            draw_text_at(CHEVRON, rect.x + rect.width - m.pad - cw, rect, m, STYLE.text_dim);
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

// Ouvre une liste : ses éléments sont (RE)construits ici, à partir de la source telle
// qu'elle est maintenant — une source modifiée par le programme se voit donc à l'ouverture
// suivante, sans rien coûter par frame.
//
// Les libellés sont calculés AVANT toute allocation : value_to_string peut appeler la
// méta-méthode `__str` d'une instance, donc du code Ollin, qui pourrait déclarer un widget
// et réallouer s_nodes.
void open_list(int slot) {
    Value source = s_nodes[slot].source;
    uint32_t gen = s_nodes[slot].gen;
    auto items = ui_list_items(source);
    // La construction des libellés a pu exécuter du code Ollin (méta-méthode `__str`), donc
    // ui.clear ou element.remove : la liste n'existe peut-être plus.
    if (!node_alive(slot, gen))
        return;
    // Anciens éléments retirés : la source a pu changer, et un doublon s'accumulerait à
    // chaque ouverture.
    std::vector<int> old_items = s_nodes[slot].children;
    for (int child : old_items)
        free_subtree(child);
    s_nodes[slot].children.clear();
    for (const auto& it : items) {
        int item_slot = alloc_node(Node::LIST_ITEM, it.first, slot);
        s_nodes[item_slot].item = it.second;
    }
    s_nav.push_back(slot);
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
    slider_set(target, on_change, integral ? (double)llround(wanted) : wanted, integral);
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
    if (CheckCollisionPointRec(p, s_head_box)) {
        s_open = !s_open;
        return true;
    }
    if (!s_open)
        return false;
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
        } else if (kind == Node::LIST) {
            open_list(slot);
        } else if (kind == Node::LIST_ITEM) {
            Value item = s_nodes[slot].item;
            int list_slot = s_nodes[slot].parent;
            Value list_target = s_nodes[list_slot].target;
            Value list_change = s_nodes[list_slot].on_change;
            if (!s_nav.empty())
                s_nav.pop_back();      // choisir referme la liste, comme un menu déroulant
            ref_set(list_target, item);
            if (list_change.is_callable())
                VM::current()->call_value(list_change, item);
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
    m.map_set(Value(std::string("list")), Value::make_builtin(ui_list));
    m.map_set(Value(std::string("menu")), Value::make_builtin(ui_menu));
    m.map_set(Value(std::string("show")), Value::make_builtin(ui_show));
    m.map_set(Value(std::string("open")), Value::make_builtin(ui_open));
    m.map_set(Value(std::string("close")), Value::make_builtin(ui_close));
    m.map_set(Value(std::string("toggle")), Value::make_builtin(ui_toggle));
    m.map_set(Value(std::string("back")), Value::make_builtin(ui_back));
    m.map_set(Value(std::string("current")), Value::make_builtin(ui_current));
    m.map_set(Value(std::string("clear")), Value::make_builtin(ui_clear));
    return m;
}
