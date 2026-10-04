// A live read-out of what the page sees of its own viewport, drawn ON the page. It exists for the
// platform that cannot be reached from here (iOS Safari, installed or not): when the layout goes wrong
// after a rotation, the numbers read at that moment are the only evidence, and opening another view to
// read them would change the very position being looked at.
//
// The panel hangs off <html>, not <body>: the body is moved by pinToVisualViewport (a transform), and a
// fixed child of a transformed element is no longer fixed to the window. It is placed on the VISIBLE
// area, so it shows even when the layout has slid out of it.
const KEY = 'ollin.probe'
const LOG_LINES = 9

function stored() {
  try { return localStorage.getItem(KEY) === '1' } catch (_) { return false }
}

function remember(on) {
  try { localStorage.setItem(KEY, on ? '1' : '0') } catch (_) {}
}

function box(el) {
  if (!el) return 'none'
  const r = el.getBoundingClientRect()
  return [r.left, r.top, r.width, r.height].map((v) => Math.round(v)).join(' ')
}

function snapshot() {
  const vv = window.visualViewport
  const o = screen.orientation
  const body = document.body
  return [
    'inner   ' + innerWidth + ' x ' + innerHeight + '   outer ' + outerWidth + ' x ' + outerHeight,
    'visual  ' + (vv ? Math.round(vv.width) + ' x ' + Math.round(vv.height) + '  off ' + Math.round(vv.offsetLeft) + ',' + Math.round(vv.offsetTop) + '  page ' + Math.round(vv.pageLeft) + ',' + Math.round(vv.pageTop) + '  x' + vv.scale : 'none'),
    'scroll  ' + Math.round(scrollX) + ',' + Math.round(scrollY) + '   screen ' + screen.width + ' x ' + screen.height + '  avail ' + screen.availWidth + ' x ' + screen.availHeight,
    'turn    ' + (o ? o.type + ' ' + o.angle : '—') + '   window.orientation ' + (window.orientation === undefined ? '—' : window.orientation),
    'body    ' + box(body) + '   style h ' + (body.style.height || '—') + '  t ' + (body.style.transform || '—'),
    'toolbar ' + box(document.getElementById('toolbar')) + (body.classList.contains('kbd-editing') ? '  [kbd-editing]' : ''),
    'layout  ' + box(document.getElementById('layout')) + '   output ' + box(document.getElementById('output-pane')),
    'focus   ' + (document.activeElement ? document.activeElement.tagName + '#' + document.activeElement.id : '—'),
  ]
}

export function mountProbe(button) {
  let panel = null
  let log = []
  let timer = 0
  const t0 = performance.now()

  const place = () => {
    if (!panel) return
    const vv = window.visualViewport
    panel.style.top = (vv ? vv.offsetTop : 0) + 'px'
    panel.style.left = (vv ? vv.offsetLeft : 0) + 'px'
    panel.style.maxWidth = (vv ? vv.width : innerWidth) + 'px'
  }

  const draw = () => {
    if (!panel) return
    place()
    panel.textContent = snapshot().concat(['', '— events —'], log).join('\n')
  }

  // One line per event: what the page measured at that instant, which is what a transient state needs.
  const note = (name) => {
    const vv = window.visualViewport
    const tb = document.getElementById('toolbar')
    log.push(((performance.now() - t0) / 1000).toFixed(1) + 's ' + name + '  in ' + innerWidth + 'x' + innerHeight + '  vv ' + (vv ? Math.round(vv.height) + '@' + Math.round(vv.offsetTop) : '—') + '  bar ' + (tb ? Math.round(tb.getBoundingClientRect().top) : '—'))
    if (log.length > LOG_LINES) log = log.slice(-LOG_LINES)
    draw()
  }

  const names = [['resize', window], ['orientationchange', window], ['scroll', window], ['focusin', window], ['focusout', window]]
  const handlers = names.map(([name, target]) => {
    const fn = () => note(name)
    target.addEventListener(name, fn)
    return () => target.removeEventListener(name, fn)
  })
  const vv = window.visualViewport
  if (vv) {
    for (const name of ['resize', 'scroll']) {
      const fn = () => note('vv.' + name)
      vv.addEventListener(name, fn)
      handlers.push(() => vv.removeEventListener(name, fn))
    }
  }
  if (screen.orientation) {
    const fn = () => note('screen.change')
    screen.orientation.addEventListener('change', fn)
    handlers.push(() => screen.orientation.removeEventListener('change', fn))
  }

  const show = (on) => {
    remember(on)
    button.classList.toggle('active', on)
    if (on && !panel) {
      panel = document.createElement('pre')
      panel.style.cssText = 'position:fixed;z-index:99999;margin:0;padding:6px 8px;pointer-events:none;' +
        'font:11px/1.35 ui-monospace,Menlo,monospace;color:#9ef0b0;background:rgba(0,0,0,.82);' +
        'white-space:pre-wrap;word-break:break-all;border:1px solid #4ade80'
      document.documentElement.appendChild(panel)
      timer = setInterval(draw, 500)
      note('probe on')
    } else if (!on && panel) {
      clearInterval(timer)
      panel.remove()
      panel = null
    }
  }

  const toggle = () => show(!panel)
  button.addEventListener('click', toggle)
  if (stored()) show(true)

  return () => {
    button.removeEventListener('click', toggle)
    handlers.forEach((off) => off())
    clearInterval(timer)
    if (panel) panel.remove()
  }
}
