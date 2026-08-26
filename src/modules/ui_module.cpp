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

// The `ui` module: widgets drawn by the ENGINE.
// A stack anchored to the top right of the drawing area. No DOM dependency: the same code serves the
// native build, Xvfb and the playground.
//
//   ui.button("Replay", replay)
//   ui.checkbox("Grid", ref grid [, onChange])
//   var settings = ui.menu("Settings")   -- a container, with the same methods
//   ui.show(settings)                    -- replaces the global menu on display
//   ui.back()                            -- goes up one level
//
// The MODEL: a widget is declared ONCE, at file level or in setup(); the engine keeps it, draws it and
// hit-tests it every frame. Nothing to call from draw().
//
// OPENING: at startup the interface is CLOSED, reduced to a three-bar handle in the corner. Clicking
// it unfolds the menu on display, whose header row carries the handle and the title; clicking that
// header closes it again. From a script: ui.open([menu]), ui.close(), ui.toggle(); ui.show(menu) also
// unfolds, since showing means making visible.
//
// NAVIGATION: one menu is on display at a time. s_nav is the current stack — s_nav[0] is the global
// menu, the implicit root by default, and the rest is the descent into submenus. Clicking a submenu
// pushes, the "<" row pops.
//
// The click is handled BEFORE mouse_poll (see ui_poll), so clicking a widget does not also fire the
// script's mouse.pressed.

namespace {

struct Node {
    // LIST is the "label: selection" row; LIST_ITEM is a row of the opened list, generated at opening
    // time as a child of the LIST node — so it is drawn and hit-tested by the menu machinery already
    // in place, with no notion of a "virtual" row.
    enum Kind { BUTTON, CHECKBOX, SLIDER, MENU, LIST, LIST_ITEM };
    Kind kind = BUTTON;
    std::string label;
    Value action;      // a button: the function called on a click
    Value target;      // a checkbox: the reference (`ref x`) to the bound variable
    Value on_change;   // a checkbox or a slider: an optional function called after a change
    double vmin = 0.0;     // slider: the range's bounds
    double vmax = 1.0;
    double vdefault = 0.0; // a slider: the value to use when the bound variable is nil
    bool integral = false; // a slider: integer bounds give an integer value
    Value source;      // a list: the array, map or enum the items come from
    Value item;        // a list item: the value, or the key, the selection returns
    std::vector<int> children;   // a menu: the slots of its content, in declaration order
    int parent = -1;
    uint32_t gen = 1;   // incremented on release, which makes a stale handle detectable
    bool alive = false;
    // Geometry of the last frame drawn, reused by the hit test so that the clickable area is EXACTLY
    // what is displayed.
    Rectangle box = {0, 0, 0, 0};
};

// A table with stable identities: a handle carries {slot, gen} and never a pointer, since the vector
// reallocates as soon as a widget is declared from a callback.
std::vector<Node> s_nodes;
std::vector<int> s_free;
int s_root = -1;
std::vector<int> s_nav;
Rectangle s_back_box = {0, 0, 0, 0};   // the back row of the frame that was drawn
// The interface is CLOSED at startup, reduced to a handle in the corner, so it does not hide the scene
// of a program that only uses it occasionally.
bool s_open = false;
Rectangle s_head_box = {0, 0, 0, 0};   // the closed handle, or the open head row
// The slider being dragged: tracking spans several frames, so the node is remembered by identity — a
// slot alone could have been recycled between two frames.
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
    // The slot is reusable: without this clearing, the next node to occupy it would inherit the
    // departed one's rectangle and be clickable before it is ever drawn.
    n.box = {0, 0, 0, 0};
    s_free.push_back(slot);
}

int ui_root() {
    if (s_root < 0 || !s_nodes[s_root].alive)
        s_root = alloc_node(Node::MENU, std::string(), -1);
    return s_root;
}

// The stack must never point at a freed menu: after a removal it is truncated to the first ancestor
// still alive, otherwise we would display nothing at all.
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

// Script-side handles: a native class instance carrying {slot, gen}.

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

// ALL the appearance lives here and NOWHERE else: colours, thicknesses and proportions. The sizes are
// FRACTIONS of the drawing area's height, as in the joystick example: the canvas is in physical
// pixels — several per display pixel on mobile — so fixed sizes would give an interface unreadable
// there and enormous elsewhere. Changing the style is a matter of editing this single block, because
// the rendering reads no appearance value inline.
struct Style {
    Color bg;
    Color bg_hover;
    Color border;     // the discreet outline of the checkboxes and of the track
    Color text;
    Color text_dim;   // a slider's value, a sub-menu's chevron
    Color accent;     // a ticked box, and the filled part of a track
    Color track;      // the background of a slider's track
    float round;      // arrondi des lignes, 0 = angles droits
    float border_thick;
    float font_frac;  // the font, as a fraction of the area's height
    float font_min;   // below this it is unreadable, whatever the area
    float pad_frac;   // the inner padding, as a fraction of the font
    float row_frac;   // a row's height
    float slider_row_frac;   // the height of a slider row: the label plus the track
    float gap_frac;   // espace entre deux lignes
    float margin_frac;// the margin at the area's edge
    float box_frac;   // the side of a checkbox's square
    float check_inset;// the fill's inset within the square, as a fraction of it
    float track_frac; // the track's thickness
    float bar_thick_frac;  // the thickness of one bar of the handle, as a fraction of the square
    float bar_gap_frac;    // the gap between two bars (0.124 × 21.6 is about 2 px of separation
                           // for a 600 px tall area; see metrics)
    float bar_width_frac;  // the bars' width, as a fraction of the square
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

// Widgets are always drawn with the engine's default font, whatever font the script chose for its own
// drawing: the interface keeps its appearance no matter what the program does.
Font ui_font() {
    return engine_font(engine_font_default());
}

float text_width(const std::string& text, float font_size) {
    Font font = ui_font();
    if (font.texture.id == 0 || font.baseSize == 0)
        return (float)text.size() * font_size * 0.5f;   // sans canvas : estimation
    return MeasureTextEx(font, text.c_str(), font_size, font_size / (float)font.baseSize).x;
}

// Label of the back row: "<" followed by the parent menu, the root being anonymous.
std::string back_label() {
    if (s_nav.size() < 2)
        return std::string();
    const std::string& parent = s_nodes[s_nav[s_nav.size() - 2]].label;
    return parent.empty() ? std::string(BACK_MARK) : std::string(BACK_MARK) + " " + parent;
}

// Slider: the bound variable is the ONLY source of truth.
// The node does not remember the current value: it is read from the variable every frame, so the
// script can write it itself and the slider follows.
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

// Writes the value when it changed, then notifies. The comparison is against the variable's RAW
// content and never against the clamped value: otherwise a variable out of range — 20 for a 1..10
// slider — would stay as it is, since dragging onto the stop would never write. Nothing identical is
// written, or holding the handle still would call the callback every frame.
void slider_set(const Value& target, const Value& on_change, double value, bool integral) {
    Value current = ref_get(target);
    if (current.is_number() && current.as_num() == value)
        return;
    Value v = integral ? Value((int64_t)llround(value)) : Value(value);
    ref_set(target, v);
    if (on_change.is_callable())
        VM::current()->call_value(const_cast<Value&>(on_change), v);
}

// Label of the item a list has selected. The target is passed by COPY, because reading a reference
// runs a script getter, which can reallocate s_nodes.
std::string list_text(const Value& target) {
    Value cur = ref_get(target);
    return cur.is_nil() ? std::string("—") : value_to_string(cur);
}

// Language-level value equality, the one used for map keys: an integer and a float of the same value
// are identical, and strings compare by interned pointer.
bool same_item(const Value& a, const Value& b) {
    return ValueEqual{}(a, b);
}

float row_height(Node::Kind kind, const Metrics& m) {
    return kind == Node::SLIDER ? m.slider_row : m.row;
}

// The slider's usable span: it is what turns an abscissa into a value, both when drawing and when
// clicking — one single truth, so the handle really is where one thinks one is clicking.
Rectangle slider_track(const Rectangle& rect, const Metrics& m) {
    return {rect.x + m.pad, rect.y + rect.height - m.pad - m.track, rect.width - 2 * m.pad, m.track};
}

// Width shared by every row: that of the widest, so the stack lines up.
float stack_width(const Metrics& m, const std::vector<int>& rows) {
    float widest = text_width(back_label(), m.font);
    // Header row: the handle plus the title of the menu on display.
    float head = m.row + text_width(s_nodes[current_menu()].label, m.font);
    if (head > widest)
        widest = head;
    for (int slot : rows) {
        // Fields are COPIED, with no reference into the node: a list's width needs the selected
        // value, and reading it runs a script getter, which can declare a widget and reallocate
        // s_nodes.
        Node::Kind kind = s_nodes[slot].kind;
        float need = text_width(s_nodes[slot].label, m.font);
        if (kind == Node::CHECKBOX || kind == Node::LIST_ITEM)
            need += m.box + m.pad;   // a checkbox, or the mark of the item selected
        if (kind == Node::MENU)
            need += m.pad + text_width(CHEVRON, m.font);
        if (kind == Node::SLIDER) {
            // Room for the value shown on the right: the wider of the two bounds.
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

// The target is taken by COPY and never from s_nodes: reading a reference calls a script getter,
// which can declare a widget and reallocate the table.
bool checkbox_state(const Value& target) {
    return !is_falsy(ref_get(target));
}

// Toggling a checkbox: writes the bound variable then notifies. The same copy requirement applies.
void toggle_checkbox(const Value& target, const Value& on_change) {
    Value state = Value(checkbox_state(target) ? int64_t(0) : int64_t(1));
    ref_set(target, state);
    if (on_change.is_callable())
        VM::current()->call_value(const_cast<Value&>(on_change), state);
}

} // namespace


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
    // EVERYTHING that calls into the script — here reading the reference — happens BEFORE the node is
    // allocated: a getter can declare a widget, hence reallocate s_nodes, and a reference obtained
    // before the call would then point at freed memory.
    // The slider is an INTEGER one only when the bounds AND the starting value are: otherwise a 0..1
    // slider driving a floating factor would round to 0 or 1.
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

// A list is SINGLE-selection: the row shows the selected item, and a click opens the list — through
// the submenu machinery — to choose another. The items are NOT generated here but at opening time, so
// the list follows changes to its source without recomputing anything per frame.
static int add_list(CallCtx& ctx, const Value* args, int argc, int parent) {
    ui_check_list_args(args, argc);
    ui_list_init(args);   // calls the script (getter/setter), hence BEFORE allocating the node
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

// A menu's methods: the receiver is args[0], the user arguments follow.

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


// element.open() unfolds this menu — or this list — from the menu on display, which is also what a
// click on its row does. It pushes, so ui.back() goes back.
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

// ui.show(menu) replaces the global menu on display and resets the navigation stack, so ui.back() does
// not go back through it. ui.show(nil) returns to the root menu.
static int ui_show(CallCtx& ctx) {
    int slot;
    if (ctx.argc < 1 || ctx.args[0].is_nil())
        slot = ui_root();
    else
        slot = menu_slot(ctx.args[0], "ui.show");
    s_nav.clear();
    s_nav.push_back(slot);
    s_open = true;   // showing implies unfolding
    return ctx.ret(Value{});
}

// ui.open([menu]) unfolds the interface, on the given menu when one is passed.
static int ui_open(CallCtx& ctx) {
    if (ctx.argc > 0 && !ctx.args[0].is_nil()) {
        int slot = menu_slot(ctx.args[0], "ui.open");
        s_nav.clear();
        s_nav.push_back(slot);
    }
    s_open = true;
    return ctx.ret(Value{});
}

// ui.close() folds the interface back to its handle, without changing the menu on display.
static int ui_close(CallCtx& ctx) {
    s_open = false;
    return ctx.ret(Value{});
}

static int ui_toggle(CallCtx& ctx) {
    s_open = !s_open;
    return ctx.ret(Value{});
}

// ui.back() goes up one level; it has no effect on the global menu, whose stack has one entry.
static int ui_back(CallCtx& ctx) {
    if (s_nav.size() > 1)
        s_nav.pop_back();
    return ctx.ret(Value{});
}

static int ui_current(CallCtx& ctx) {
    return ctx.ret(make_handle(current_menu()));
}


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

// ui.clear() empties EVERYTHING and restores the root menu; every handle becomes stale.
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

// Computes the geometry of the displayed rows and stores it in each node. Called by the rendering; the
// hit test reuses those rectangles, so there is a single truth.
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

// Three bars drawn by hand: the default font has no menu glyph, and a drawn shape follows the style
// without depending on the character set.
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
        // An empty interface: not even a handle, and above all no leftover clickable area, since the
        // hit test reads these rectangles.
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
        // The title of the menu on display only makes sense when open: closed, the stack is just the
        // handle.
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
        // Local copies: reading a checkbox's state calls a script closure, which could declare a
        // widget and reallocate s_nodes under our feet.
        Rectangle rect = s_nodes[slot].box;
        Node::Kind kind = s_nodes[slot].kind;
        std::string label = s_nodes[slot].label;
        Value target = s_nodes[slot].target;
        bool checked = kind == Node::CHECKBOX && checkbox_state(target);
        draw_row(rect, CheckCollisionPointRec(mouse, rect));
        // A slider reserves the bottom of its row for the track, so the text is centred in what
        // remains.
        Rectangle text_rect = rect;
        if (kind == Node::SLIDER)
            text_rect.height = rect.height - m.track - m.pad;
        float tx = rect.x + m.pad;
        if (kind == Node::LIST_ITEM) {
            // A round mark for the selected item, like a radio button: single selection reads at a
            // glance, and the shape sets it apart from the square checkbox.
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
            // The label on the left, at the same abscissa as a button's, and the square on the
            // right, where a slider's value, a list's value and a sub-menu's chevron already sit:
            // one single reading order for the whole stack. Every square being the same size, their
            // left edges line up on their own, without a column having to be computed.
            Rectangle box = {rect.x + rect.width - m.pad - m.box, rect.y + (m.row - m.box) * 0.5f, m.box, m.box};
            DrawRectangleRoundedLinesEx(box, STYLE.round, 6, STYLE.border_thick, STYLE.border);
            if (checked) {
                float inset = m.box * STYLE.check_inset;
                Rectangle fill = {box.x + inset, box.y + inset, m.box - 2 * inset, m.box - 2 * inset};
                DrawRectangleRounded(fill, STYLE.round, 6, STYLE.accent);
            }
        }
        if (kind == Node::SLIDER) {
            double vmin = s_nodes[slot].vmin;
            double vmax = s_nodes[slot].vmax;
            double value = slider_value(target, vmin, vmax, s_nodes[slot].vdefault);
            bool integral = s_nodes[slot].integral;
            Rectangle track = slider_track(rect, m);
            DrawRectangleRounded(track, 1.0f, 6, STYLE.track);
            float t = (float)((value - vmin) / (vmax - vmin));
            // A fill shorter than its own rounding would degenerate, so only the useful part is
            // drawn, and never less than the track's thickness.
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

// The value denoted by the cursor's abscissa on a slider's track.
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

// Opens a list: its items are (RE)built here from the source as it stands now, so a source the program
// has modified shows up at the next opening, at no per-frame cost.
//
// The labels are computed BEFORE any allocation: value_to_string may call an instance's __str
// meta-method, hence Ollin code, which could declare a widget and reallocate s_nodes.
void open_list(int slot) {
    Value source = s_nodes[slot].source;
    uint32_t gen = s_nodes[slot].gen;
    auto items = ui_list_items(source);
    // Building the labels may have run Ollin code (the __str meta-method), hence ui.clear or
    // element.remove: the list may no longer exist.
    if (!node_alive(slot, gen))
        return;
    // The old items are removed: the source may have changed, and duplicates would pile up on every
    // opening.
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

// A drag in progress: the value follows the cursor as long as the button is held, and the click stays
// consumed — otherwise releasing over the scene would make it react.
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
    // The rectangles come from the last frame drawn, so what one sees is what one clicks. Before the
    // first frame no row has a box, and therefore no click lands.
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
        // COPY before calling anything: the callback, or the reference's setter, can declare a widget
        // or call ui.clear and thus reallocate s_nodes. Passing a field by reference would leave a
        // dangling reference DURING the call.
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
            // The click sets the value immediately, then the drag takes over until release.
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
                s_nav.pop_back();      // choosing closes the list, as a drop-down does
            ref_set(list_target, item);
            if (list_change.is_callable())
                VM::current()->call_value(list_change, item);
        } else {
            s_nav.push_back(slot);
        }
        return true;   // the click is consumed, and must not reach mouse.pressed
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
