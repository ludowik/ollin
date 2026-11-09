// The text a program types, on a phone: keyboard.typed(text), keyboard.show() and keyboard.hide() (src/modules/keyboard_module.cpp).
//
// A <canvas> is no text field, so no browser opens its keyboard for one. The page therefore keeps an INVISIBLE
// contenteditable element, the "sink", and takes the focus for it. Measured on an iPhone, with a probe page that has since been removed:
//  - focus() raises the keyboard only INSIDE the gesture of a tap. The engine learns of a tap one frame later, so a
//    script's show() could never do it alone;
//  - an element focused with inputmode="none" takes the focus WITHOUT a keyboard, and setting inputmode="text" on it
//    later, outside any gesture, raises the keyboard and keeps the focus. That is the whole trick: the tap ARMS the
//    sink (focus, no keyboard), the script's show() releases it (inputmode "text");
//  - the engine learns of a touch at its touchstart (it is what raylib reports), so a script's show() runs while the finger
//    is STILL DOWN, before the page can arm anything: the page may take the focus only at touchend, inside the gesture.
//    So show() never takes the focus itself: it remembers the request, and the touchend that ends the tap answers it by
//    focusing with inputmode "text" at once. A show() that finds the sink armed already (an earlier tap did it) switches
//    the inputmode at once. Taking the focus from show() was the first version, and a real iPhone showed it: the keyboard
//    came only from the second tap on, once an earlier touchend had left the sink focused;
//  - the browser must not move the focus when the canvas is touched: preventDefault on touchstart and touchend, which
//    also cancels the emulated mouse events that would blur the sink. Without it the keyboard still came up, but the
//    sink had lost the focus and typed nothing.
//  - the keyboard SHRINKS the window on some browsers, and the pane that holds the canvas follows it: the engine then
//    resizes its area (graphics.fitArea) or scales the whole canvas down to fit, and a screen "shrinks" as the keyboard
//    comes up. So while the sink has the focus the pane keeps the size it had when the focus was taken (freeze), and the
//    keyboard simply covers the bottom of it. A real rotation (the orientation changes) lets it go.
// Programs that declare neither keyboard.typed nor a ui.textField ("wanted" stays false) are not touched at all.
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

  // What the page saw, newest last, for keyboard.trace() and the keyboard diagnostic example: on a phone this is the only way
  // to learn which events a keyboard really sends (the "done" key, a swipe), and in what order.
  const log = []
  const t0 = performance.now()
  function note(what) {
    log.push(((performance.now() - t0) / 1000).toFixed(2) + ' ' + what)
    if (log.length > 60) log.shift()
  }

  let queue = ''
  let shown = false
  let composing = false
  let dismissed = false     // the user took the focus away (the "done" key of a phone, a swipe): the engine ends a field's edit
  let closing = false       // hide() and reset() blur the sink themselves, which is no dismissal
  let askedAt = -Infinity   // when show() found no armed sink and left its request to the next touchend
  const ASK_LIFETIME = 1500 // ms: a request that old is no tap's, and the touchend of a later tap must not answer it

  // The pane keeps the size it had at the focus: an explicit size, no flex. Nothing changes size, so the observers of the
  // host (watchRenderArea) and of the engine (the scale-to-fit of the canvas) see nothing.
  let frozen = null
  const orientation = () => (screen.orientation ? screen.orientation.type : String(window.orientation))
  function freeze() {
    if (frozen) return
    const pane = canvas.parentElement
    if (!pane) return
    const box = pane.getBoundingClientRect()
    if (!(box.width > 0 && box.height > 0)) return
    frozen = { pane, orientation: orientation(), flex: pane.style.flex, width: pane.style.width, height: pane.style.height }
    pane.style.flex = 'none'
    pane.style.width = box.width + 'px'
    pane.style.height = box.height + 'px'
  }
  function thaw() {
    if (!frozen) return
    frozen.pane.style.flex = frozen.flex
    frozen.pane.style.width = frozen.width
    frozen.pane.style.height = frozen.height
    frozen = null
  }
  const onResize = () => {
    if (frozen && orientation() !== frozen.orientation) thaw()
  }
  window.addEventListener('resize', onResize)
  const vv = window.visualViewport
  const noteViewport = (what) => note(what + ' inner ' + window.innerHeight + (vv ? ' visual ' + Math.round(vv.height) : '') +
    ' sink=' + focused())
  const onNoteResize = () => noteViewport('resize')
  const onNoteVisualResize = () => noteViewport('visual resize')
  window.addEventListener('resize', onNoteResize)
  if (vv) vv.addEventListener('resize', onNoteVisualResize)

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

    // Whether the user closed the keyboard since the last call, which a text field takes for "done".
    takeDismissed() {
      const was = dismissed
      dismissed = false
      if (was) note('engine took the dismissal')
      return was
    },

    // The last lines of what the page saw, as one text.
    trace(count) {
      return count > 0 ? log.slice(-count).join('\n') : ''    // slice(-0) would be the whole log
    },

    // Lets the keyboard come. An armed sink only needs its inputmode changed; otherwise the tap that is going on has not
    // reached its touchend yet, which is the only place the focus can be taken (see the head of this file).
    show() {
      note('show() ' + (focused() ? 'focused: inputmode text' : 'asked, waiting for a touchend'))
      if (blocked()) return
      if (focused()) {
        sink.inputMode = 'text'
        shown = true
        return
      }
      askedAt = performance.now()
    },

    hide() {
      note('hide()')
      shown = false
      dismissed = false
      askedAt = -Infinity
      sink.inputMode = 'none'
      closing = true
      sink.blur()
      closing = false
    },

    // A new program: no keyboard left up, nothing wanted, nothing typed.
    reset() {
      api.wanted = false
      queue = ''
      shown = false
      askedAt = -Infinity
      composing = false
      dismissed = false
      sink.inputMode = 'none'
      closing = true
      sink.blur()
      closing = false
      sink.textContent = ''
    },
  }
  window.__ollinTextInput = api

  // Takes the focus for the sink inside the tap, at its touchend: without a keyboard, unless show() asked for one while the
  // finger was down. Then the focus is taken with inputmode "text" from the start, which is the case an iPhone was
  // measured to accept (a focus() inside a gesture, on an element that wants a keyboard).
  function arm() {
    if (!api.wanted || blocked() || shown) return
    dismissed = false
    const asked = performance.now() - askedAt < ASK_LIFETIME
    note('touchend arms the sink, asked=' + asked)
    askedAt = -Infinity
    sink.inputMode = asked ? 'text' : 'none'
    if (asked) shown = true
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

  sink.addEventListener('focus', () => {
    note('sink focus')
    freeze()
  })
  sink.addEventListener('keydown', (e) => note('keydown ' + e.key))
  sink.addEventListener('blur', () => {
    note('sink blur' + (closing ? ' (engine)' : '') + (shown ? ' while shown' : ''))
    if (!closing && shown) dismissed = true
    shown = false
    composing = false
    thaw()
  })
  sink.addEventListener('compositionstart', () => { composing = true })
  sink.addEventListener('compositionend', (e) => {
    composing = false
    if (e.data) queue += plain(e.data)
    sink.textContent = ''   // the last input event of a composition came while it was still on: the sink must not keep the word
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
    window.removeEventListener('resize', onResize)
    window.removeEventListener('resize', onNoteResize)
    if (vv) vv.removeEventListener('resize', onNoteVisualResize)
    thaw()
    sink.remove()
  }
}
