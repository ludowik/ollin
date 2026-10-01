#pragma once
#include "value.h"

// The `motion` module: the phone's ORIENTATION and its ACCELERATION.
//
//   motion.enable()          ask for the sensors; returns the state, as motion.state() does
//   motion.state()           "off" (enable() never called), "pending" (waiting for the permission or
//                            for the first reading), "on", "denied" or "unsupported"
//   motion.tilt()            roll, pitch — degrees, in the frame of the SCREEN as the user holds it
//   motion.gravity()         x, y, z — the accelerometer's rest reading, m/s², screen frame
//   motion.acceleration()    x, y, z — the device's own acceleration, gravity removed, m/s²
//   motion.attitude()        a Quat taking the screen frame to the 3D world (Y up), or nil
//
// Every reading is zero (attitude: nil) unless the state is "on", so a script can read them without
// testing first and test the state only to choose a control scheme.
//
// There is no rotation rate: Chromium assigns the gyroscope's x, y and z to the event's alpha, beta and
// gamma, where the spec says z, x and y (measured with sensor emulation), so the axes of a raw rate
// cannot be trusted to agree between browsers. The orientation and the acceleration do agree.
//
// Everything comes from the browser (DeviceOrientationEvent, DeviceMotionEvent): raylib has no sensor
// API. Outside the browser the module exists in full and its state is "unsupported".
Value make_motion_module();

// Samples the sensors once for the frame. To be called before the input callbacks, so that every
// reading a callback takes is the frame's.
void motion_begin_frame();

// When a program starts: it must call enable() again, a previous program's request being its own.
void motion_reset();
