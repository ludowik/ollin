#pragma once
#include "value.h"

// The `touch` module: MULTITOUCH — several fingers tracked at once, each by a stable identifier.
//
// raylib gives a SNAPSHOT of the contacts each frame — how many, where, which identifiers — but no
// events: the engine compares this frame's list with the previous one to deduce that a finger
// landed, moved or lifted. That tracking is what was missing, and without it `mouse` can report
// only one point, since raylib emulates the mouse only while exactly one finger touches the
// screen.
//
// The script assigns whichever functions it wants and the engine calls those that exist:
//   touch.began(id, x, y)  a finger landed
//   touch.moved(id, x, y)  a finger moved
//   touch.ended(id, x, y)  a finger lifted (last known position)
//   touch.pinch(scale, cx, cy)  two fingers spread or closed — the zoom gesture
// The state can also be read directly, through touch.count() and touch.points().
//
// `pinch` is DERIVED from two contacts, and computed here rather than in every script: identifying
// the pair, re-arming the reference distance when it changes and keeping two fingers on the same
// point out of a division are three traps, and a wheel handler alone leaves a phone with no zoom.
//
// The `mouse` callbacks are NOT suppressed for all that: with a single finger the system emulates
// the mouse, so a script declaring both families receives the gesture twice. It is up to the
// script to choose which one it listens to.
Value make_touch_module();

// Samples this frame's contacts. To be called BEFORE every other input callback, since a
// `mouse` callback reading touch.count() must see THIS frame's fingers.
void touch_begin_frame();

// Compares the sample with the previous frame's and calls began, moved and ended.
void touch_poll();

// When a program starts: forget the previous one's contacts, otherwise a finger still listed as
// down would look like a gesture in progress.
void touch_reset();
