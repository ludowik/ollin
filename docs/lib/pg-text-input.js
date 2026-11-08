// The text a program types, on a phone: keyboard.typed(text), keyboard.show() and keyboard.hide() (src/modules/keyboard_module.cpp).
//
// A <canvas> is no text field, so no browser opens its keyboard for one. The page therefore keeps an INVISIBLE
// contenteditable element, the "sink", and takes the focus for it. Measured on an iPhone (docs/keyboard-probe.html):
//  - focus() raises the keyboard only INSIDE the gesture of a tap. The engine learns of a tap one frame later, so a
//    script's show() could never do it alone;
//  - an element focused with inputmode="none" takes the focus WITHOUT a keyboard, and setting inputmode="text" on it
//    later, outside any gesture, raises the keyboard and keeps the focus. That is the whole trick: the tap ARMS the
//    sink (focus, no keyboard), the script's show() releases it (inputmode "text");
//  - the browser must not move the focus when the canvas is touched: preventDefault on touchstart and touchend, which
//    also cancels the emulated mouse events that would blur the sink. Without it the keyboard still came up, but the
//    sink had lost the focus and typed nothing.
// Programs that never declare keyboard.typed ("wanted" stays false) are not touched at all.
//
// The engine and this module meet in window.__ollinTextInput: the engine calls frame(wanted) once per frame, show() and
// hide(). Only the text of the sink comes through here; the control keys (backspace, return…) bubble from the sink to
// the window as they always did, where the engine reads them as key names.

// The characters an iPhone puts in place of the straight quote and apostrophe ("smart punctuation", which the page cannot
// switch off): a name typed with "'" must reach the program with "'".
function plain(text) {
  return text.replace(/[‘’]/g, "'").replace(/[“”]/g, '"')
}

export function installTextInput(canvas) {
  const sink = document.createElement('div')
  sink.contentEditable = 'true'
  sink.setAttribute('virtualkeyboardpolicy', 'manual')
  sink.setAttribute('inputmode', 'none')
  sink.setAttribute('autocorrect', 'off')
  sink.setAttribute('autocapitalize', 'off')
  sink.setAttribute('spellcheck', 'false')
  sink.setAttribute('role', 'textbox')
  sink.setAttribute('aria-label', 'Text typed to the running program')
  // Small and nearly invisible, with a 16px font so that iOS does not zoom the page when it takes the focus.
  sink.style.cssText = 'position:fixed;left:0;bottom:0;width:1px;height:1px;padding:0;margin:0;border:0;opacity:0.01;' +
    'font-size:16px;color:transparent;background:transparent;caret-color:transparent;outline:none;overflow:hidden'
  document.body.appendChild(sink)

  let queue = ''
  let shown = false
  let composing = false

  const focused = () => document.activeElement === sink
  const blocked = () => !!window.__ollinKbdBlocked   // the editor of the playground has the keyboard

  const api = {
    wanted: false,

    // Called by the engine once per frame. null: the sink is not the source of text, the engine reads its own
    // keyboard; a string (possibly empty): the sink is, and this is what it received since the last frame.
    frame(wanted) {
      api.wanted = !!wanted
      if (!focused() && !queue) return null
      const text = queue
      queue = ''
      return text
    },

    // The tap armed the sink; this lets the keyboard come.
    show() {
      if (blocked()) return
      if (!focused()) {
        // No tap armed it. Outside a gesture this may be refused, and on a computer there is no keyboard to show.
        if (!(navigator.maxTouchPoints > 0)) return
        sink.focus({ preventScroll: true })
      }
      sink.inputMode = 'text'
      shown = true
    },

    hide() {
      shown = false
      sink.inputMode = 'none'
      sink.blur()
    },

    // A new program: no keyboard left up, nothing wanted, nothing typed.
    reset() {
      api.wanted = false
      queue = ''
      shown = false
      composing = false
      sink.inputMode = 'none'
      sink.blur()
      sink.textContent = ''
    },
  }
  window.__ollinTextInput = api

  // Takes the focus for the sink without a keyboard, inside the tap.
  function arm() {
    if (!api.wanted || blocked() || shown) return
    sink.inputMode = 'none'
    if (!focused()) sink.focus({ preventScroll: true })
  }

  canvas.addEventListener('touchstart', (e) => {
    if (api.wanted && !blocked() && e.cancelable) e.preventDefault()
  }, { passive: false })
  canvas.addEventListener('touchend', (e) => {
    if (!api.wanted || blocked()) return
    arm()
    if (e.cancelable) e.preventDefault()
  }, { passive: false })

  sink.addEventListener('blur', () => {
    shown = false
    composing = false
  })
  sink.addEventListener('compositionstart', () => { composing = true })
  sink.addEventListener('compositionend', (e) => {
    composing = false
    if (e.data) queue += plain(e.data)
  })
  sink.addEventListener('beforeinput', (e) => {
    if (blocked()) return
    // insertCompositionText is final only at compositionend (above); a line break or a deletion is a control key, which
    // the engine reads from keydown.
    if ((e.inputType === 'insertText' || e.inputType === 'insertFromPaste' || e.inputType === 'insertReplacementText') && e.data) {
      queue += plain(e.data)
    }
  })
  sink.addEventListener('input', () => {
    // The sink must not grow: what it holds is of no use once the event is read.
    if (!composing) sink.textContent = ''
  })

  return () => {
    if (window.__ollinTextInput === api) delete window.__ollinTextInput
    sink.remove()
  }
}
