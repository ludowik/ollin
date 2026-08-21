#include "touch_module.h"
#include "value.h"
#include "vm.h"
#include <raylib.h>
#include <string>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// Multitouch, build WITH raylib.
//
// All the work is a DIFF: raylib exposes the current state (GetTouchPointCount, GetTouchPointId,
// GetTouchPosition) and nothing else. We therefore keep the previous frame's list and compare, which
// yields the three events the script expects.
//
// BUT that list LIES in two cases, and the module cannot copy it as is:
//
// 1. Two fingers lifted in the SAME event. emscripten passes the UNION of the fingers still down
//    (e.touches) and those that have just lifted (e.changedTouches), and raylib, which removes only
//    one per event — it leaves its loop at the first — keeps the other in its list until the next
//    touch event, sometimes forever. This case is covered by CONSTRUCTION (the lifted identifier is
//    remembered) and NOT by measurement: the test harness, with its synthetic events, does not
//    reproduce it.
// 2. Focus loss (tab switched, application left): the browser sends NO touchend at all, so every
//    finger stays "down" indefinitely. IsWindowFocused() is not enough — MEASURED: with only that
//    focus test, a held note kept sounding after a blur.
//
// In both cases the script would see a phantom contact, and a note held by that contact would never
// stop. So we listen to the browser — but ONLY to remove.
//
// DIRECTION OF THE FILTER, never to be inverted: the browser is proof of a LIFT, never permission to
// press. Taking its list of pressed fingers as the truth and accepting only what it contains was
// tried, and lost contacts that were still pressed on a real phone: everything that list ignores — a
// missed event, an identifier renumbered by the graphics layer, a focus wrongly reported for as long
// as an address bar is up — became a cancellation. A doubt must leave the finger alive; only a
// touchend, a touchcancel or a focus loss kills it. The absence of regression is MEASURED: a contact
// the browser no longer mentions in any list stays alive.

namespace {

// raylib tracks up to MAX_TOUCH_POINTS contacts, 8 by default. The table has a fixed size, and one
// finger more is simply ignored, exactly as raylib itself ignores it.
constexpr int k_max_points = 8;

struct Point {
    int id = -1;
    float x = 0.0f;
    float y = 0.0f;
};

Point s_prev[k_max_points];
int s_prev_count = 0;

#ifdef __EMSCRIPTEN__
// Listening in CAPTURE on window: nothing is intercepted from raylib, which keeps its own listeners
// and its mouse emulation. Two sets, with clearly distinct roles:
//   __ollinTouchHeld — a mirror of e.touches, whose ONLY purpose is to feed the second one on blur;
//   __ollinTouchGone — the identifiers whose lift we have SEEN, the only set the filter reads.
// An identifier leaves Gone as soon as a finger presses again with that number: the browser recycles
// them, and without this the next finger would be born already dead.
void install_dom_watch() {
    static bool installed = false;
    if (installed)
        return;
    installed = true;
    EM_ASM({
        window.__ollinTouchGone = new Set();
        window.__ollinTouchHeld = new Set();
        var poses = function(e) {
            var s = new Set();
            for (var i = 0; i < e.touches.length; i++) {
                s.add(e.touches[i].identifier);
                window.__ollinTouchGone.delete(e.touches[i].identifier);
            }
            window.__ollinTouchHeld = s;
        };
        var lifted = function(e) {
            for (var i = 0; i < e.changedTouches.length; i++)
                window.__ollinTouchGone.add(e.changedTouches[i].identifier);
            poses(e);
        };
        // No array or object literal here: EM_ASM is a MACRO, and a comma outside parentheses
        // separates its arguments, at which point the block no longer compiles.
        var opt = { capture: true };
        opt.passive = true;
        var brancher = function(noms, fn) {
            var liste = noms.split(' ');
            for (var i = 0; i < liste.length; i++)
                window.addEventListener(liste[i], fn, opt);
        };
        brancher('touchstart touchmove', poses);
        brancher('touchend touchcancel', lifted);
        // Focus loss: no touchend arrives, so we declare lifted every finger we knew was down. That
        // is the only reason __ollinTouchHeld exists.
        var abandon_all = function() {
            window.__ollinTouchHeld.forEach(function(id) { window.__ollinTouchGone.add(id); });
            window.__ollinTouchHeld = new Set();
        };
        window.addEventListener('blur', abandon_all);
        document.addEventListener('visibilitychange', function() {
            if (document.hidden)
                abandon_all();
        });
    });
}

// ONE crossing of the JavaScript boundary per frame: we pass the identifiers raylib reports and get
// back, as a bit mask, those whose lift has been seen. Querying the set contact by contact cost one
// round trip per finger.
//
// The same pass FORGETS the lifted identifiers raylib no longer reports: there is then no phantom
// left to filter, and without that forgetting the set would grow for the whole session, since the
// browser does not necessarily recycle its identifiers.
int lifted_mask(const int* ids, int n) {
    return EM_ASM_INT({
        var partis = window.__ollinTouchGone;
        if (!partis)
            return 0;
        var masque = 0;
        var vus = new Set();
        for (var i = 0; i < $1; i++) {
            var id = HEAP32[($0 >> 2) + i];
            vus.add(id);
            if (partis.has(id))
                masque |= 1 << i;
        }
        partis.forEach(function(id) {
            if (!vus.has(id))
                partis.delete(id);
        });
        return masque;
    }, ids, n);
}

void forget_all_lifted() {
    EM_ASM({
        if (window.__ollinTouchGone)
            window.__ollinTouchGone.clear();
    });
}
#else
void install_dom_watch() {
}

// Outside the browser raylib's list is the only source, and simultaneous lifts do not arise: the
// desktop reports no touch contacts at all.
int lifted_mask(const int*, int) {
    return 0;
}

void forget_all_lifted() {
}
#endif

int index_of(const Point* liste, int n, int id) {
    for (int i = 0; i < n; i++) {
        if (liste[i].id == id)
            return i;
    }
    return -1;
}

Value callback(const Value& m, const char* nom) {
    return m.map_get(Value(std::string(nom)));
}

// Filtered sample of the current frame, taken ONCE by touch_begin_frame: the state count and points
// read is exactly the one the callbacks saw.
Point s_cur[k_max_points];
int s_cur_count = 0;

void sample_contacts() {
    // No focus test here: IsWindowFocused() answers false on a real phone as soon as a browser
    // ornament takes over, and it then cut off fingers that were still down.
    int brut = GetTouchPointCount();
    if (brut > k_max_points)
        brut = k_max_points;
    // No contact reported means no phantom is possible, so there is nothing to filter and the set of
    // lifted identifiers is of no further use. We cross the boundary only at the TRANSITION, since
    // otherwise a frame without a single finger — nearly all of a program — would pay a round trip to
    // receive an empty mask.
    if (brut == 0) {
        s_cur_count = 0;
        if (s_prev_count > 0)
            forget_all_lifted();
        return;
    }
    int ids[k_max_points];
    for (int i = 0; i < brut; i++)
        ids[i] = GetTouchPointId(i);
    int lifted = lifted_mask(ids, brut);
    s_cur_count = 0;
    for (int i = 0; i < brut; i++) {
        if (lifted & (1 << i))
            continue;
        Vector2 p = GetTouchPosition(i);
        s_cur[s_cur_count].id = ids[i];
        s_cur[s_cur_count].x = p.x;
        s_cur[s_cur_count].y = p.y;
        s_cur_count++;
    }
}

int touch_count(CallCtx& ctx) {
    return ctx.ret(Value((int64_t)s_cur_count));
}

// The current contacts, as an array of {id, x, y}: enough to draw visual feedback or drive a
// two-finger control without going through the callbacks.
int touch_points(CallCtx& ctx) {
    // The keys are interned once: a script reading points() every frame to draw feedback would
    // otherwise build three strings per contact per call.
    static const Value K_ID(std::string("id")), K_X(std::string("x")), K_Y(std::string("y"));
    Value arr = Value::make_array();
    for (int i = 0; i < s_cur_count; i++) {
        Value m = Value::make_map();
        m.map_set(K_ID, Value((int64_t)s_cur[i].id));
        m.map_set(K_X, Value((double)s_cur[i].x));
        m.map_set(K_Y, Value((double)s_cur[i].y));
        arr.array_push(m);
    }
    return ctx.ret(arr);
}

} // namespace

// Sampling is a frame step IN ITS OWN RIGHT, not the beginning of touch_poll: the `mouse` callbacks
// run BEFORE, and many of them query touch.count() to know whether the gesture comes from a finger
// (the system emulates the mouse for a single finger). Sampling inside touch_poll left that reading
// one frame behind — a finger already down was seen as "no contact", and the mouse emulation claimed
// the gesture. Observed: the bow in sound_demo no longer followed the finger.
void touch_begin_frame() {
    install_dom_watch();
    sample_contacts();
}

void touch_poll() {
    VM* vm = VM::current();
    Value m = vm->get_global("touch");
    if (!m.is_map())
        return;
    Value began = callback(m, "began");
    Value moved = callback(m, "moved");
    Value ended = callback(m, "ended");

    // Presses and moves: an identifier absent from the previous frame is a new finger. Three
    // arguments go through the generic form of call_value, since the VM has no three-argument
    // overload and adding one for a single caller would not be justified.
    for (int i = 0; i < s_cur_count; i++) {
        int j = index_of(s_prev, s_prev_count, s_cur[i].id);
        Value args[3] = {Value((int64_t)s_cur[i].id), Value((double)s_cur[i].x), Value((double)s_cur[i].y)};
        if (j < 0) {
            if (began.is_callable())
                vm->call_value(began, args, 3);
        } else if (moved.is_callable() && (s_cur[i].x != s_prev[j].x || s_cur[i].y != s_prev[j].y)) {
            vm->call_value(moved, args, 3);
        }
    }

    // Lifts: an identifier from the previous frame that has vanished. We report its LAST known
    // position, the one at lift-off no longer being readable since raylib removed the point.
    for (int i = 0; i < s_prev_count; i++) {
        if (index_of(s_cur, s_cur_count, s_prev[i].id) >= 0)
            continue;
        if (ended.is_callable()) {
            Value args[3] = {Value((int64_t)s_prev[i].id), Value((double)s_prev[i].x),
                             Value((double)s_prev[i].y)};
            vm->call_value(ended, args, 3);
        }
    }

    // The current list becomes the next frame's reference. It is copied AFTER the calls, so that if
    // a script callback throws, the state stays consistent.
    for (int i = 0; i < s_cur_count; i++)
        s_prev[i] = s_cur[i];
    s_prev_count = s_cur_count;
}

void touch_reset() {
    s_prev_count = 0;
    s_cur_count = 0;
}

// The module is an empty map: the script assigns began, moved and ended to it, and reads count and
// points. Same pattern as `mouse`.
Value make_touch_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("count")), Value::make_builtin(touch_count));
    m.map_set(Value(std::string("points")), Value::make_builtin(touch_points));
    return m;
}
