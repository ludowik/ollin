// TUTORIAL view — the initialisation logic, called by app.js once the views/tutorial.html
// fragment is mounted in #view.
//   init(ctx) → cleanup()    (ctx = { root, getOllin, hardReload, navigate })
// `root`       is the #view element the fragment is mounted in (the scope of querySelector).
// `getOllin()` is a promise of the SHARED WASM module (a single instance for the whole app).
// `hardReload` is a cache-cleared reload (the "Reload" button, or pull-to-refresh).
import {
  EditorState,
  EditorView, lineNumbers,
  syntaxHighlighting,
} from '../vendor/codemirror.js'
import { CODE_DISPLAY, CODE_THEME_BASE, ICONS } from '../lib/cm-shared.js'
import { ollinLang, ollinHighlight } from '../lib/cm-lang.js'

// Editor theme, for the tutorial's read-only blocks.
const ollinTheme = EditorView.theme({
  '&': { background: '#1a1d2e', color: '#dde4ef', border: '1px solid #3a3f63', borderRadius: '8px', fontSize: 'var(--code-size)' },
  '.cm-scroller': { fontFamily: "'JetBrains Mono','Fira Code','Cascadia Code',Consolas,monospace", lineHeight: '1.65', overflow: 'auto', fontSize: 'var(--code-size)' },
  '.cm-content': { padding: '14px 0', caretColor: '#9ba1ff', fontSize: 'var(--code-size)' },
  ...CODE_DISPLAY,
  ...CODE_THEME_BASE,   // active line, cursor, selection (shared)
  '.cm-gutters': { background: '#1a1d2e', color: '#5a628a', border: 'none', borderRight: '1px solid #3a3f63', borderRadius: '8px 0 0 8px' },
  '&.cm-focused': { outline: 'none', borderColor: '#9ba1ff' },
  '.cm-content[contenteditable="false"]': { cursor: 'default' },
})

const BASE_EXT = [ollinLang, syntaxHighlighting(ollinHighlight), lineNumbers(), ollinTheme, EditorView.lineWrapping]

function makeStaticEditor(parent, code) {
  return new EditorView({
    state: EditorState.create({ doc: code, extensions: [...BASE_EXT, EditorView.editable.of(false), EditorState.readOnly.of(true)] }),
    parent,
  })
}

// SVG icons (run, copy, ok), shared through cm-shared.js.

function makeCopyBtn(getText) {
  const btn = document.createElement('button')
  btn.className = 'code-btn copy'
  btn.title     = 'Copier'
  btn.innerHTML = ICONS.copy
  btn.addEventListener('click', () => {
    navigator.clipboard.writeText(getText()).then(() => {
      btn.innerHTML         = ICONS.ok
      btn.style.color       = '#4ade80'
      btn.style.borderColor = '#4ade80'
      setTimeout(() => { btn.innerHTML = ICONS.copy; btn.style.color = ''; btn.style.borderColor = '' }, 1500)
    })
  })
  return btn
}

export async function init(ctx) {
  const root = ctx.root
  const disposers = []          // cleanup when the view is unmounted
  const editors   = []          // the static CM6 editors created, to destroy on unmount

  // SHARED execution (pg-run.js): the same preloading and error handling as the playground and
  // the standalone mode (try/catch, graphics frame errors).
  const Run = await import('../lib/pg-run.js?v=' + ctx.v)

  // The WASM runtime is SHARED, loaded once by app.js. We warm it up as soon as the view is
  // entered; the Run buttons wait for it if it is not ready.
  let ollin = null
  ctx.getOllin().then(m => { ollin = m }).catch(err => console.error('WASM init:', err))

  // Hamburger menu (mobile).
  const ham      = root.querySelector('#ham')
  const navEl    = root.querySelector('#nav')
  const backdrop = root.querySelector('#backdrop')
  if (ham && navEl && backdrop) {
    const closeNav = () => { navEl.classList.remove('open'); backdrop.classList.remove('visible'); ham.classList.remove('open') }
    const openNav  = () => { navEl.classList.add('open'); backdrop.classList.add('visible'); ham.classList.add('open') }
    ham.addEventListener('click', () => navEl.classList.contains('open') ? closeNav() : openNav())
    backdrop.addEventListener('click', closeNav)
    // A click on a section link (or a view link) closes the menu.
    navEl.querySelectorAll('a').forEach(a => a.addEventListener('click', closeNav))
  }

  // The active nav entry follows the scrolling.
  const navLinks  = root.querySelectorAll('nav a[href^="#"]')
  const scrollObs = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (e.isIntersecting) {
        navLinks.forEach(l => l.classList.remove('active'))
        const l = root.querySelector(`nav a[href="#${e.target.id}"]`)
        if (l) l.classList.add('active')
      }
    })
  }, { rootMargin: '-20% 0px -70% 0px' })
  root.querySelectorAll('section[id]').forEach(s => scrollObs.observe(s))
  disposers.push(() => scrollObs.disconnect())

  // Remembering the reading position, restored on refresh. Only an entry WITHOUT an explicit
  // anchor (a bare #/tutorial, or a refresh) restores it — a section link (#intro, #for…) keeps
  // priority.
  const SCROLL_KEY = 'ollin-tutorial-scrollY'
  let scrollSaveQueued = false
  const onScroll = () => {
    if (scrollSaveQueued) return
    scrollSaveQueued = true
    requestAnimationFrame(() => {
      scrollSaveQueued = false
      try { localStorage.setItem(SCROLL_KEY, String(window.scrollY)) } catch (_) {}
    })
  }
  addEventListener('scroll', onScroll, { passive: true })
  disposers.push(() => removeEventListener('scroll', onScroll))

  if (!ctx.anchor) {
    let savedY = 0
    try { savedY = parseInt(localStorage.getItem(SCROLL_KEY) || '0', 10) || 0 } catch (_) {}
    if (savedY > 0) {
      // Two rAFs: they give the CM6 editors (mounted further down) time to settle the final
      // height of the content before the target scroll is computed.
      requestAnimationFrame(() => requestAnimationFrame(() => window.scrollTo(0, savedY)))
    }
  }

  // Pull-to-refresh (mobile): dragging the page down while at the very top triggers a
  // cache-cleared reload.
  const content = root.querySelector('main')
  const ind = document.createElement('div')
  ind.id = 'ptr-indicator'
  ind.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-2.64-6.36"/><path d="M21 3v6h-6"/></svg>'
  Object.assign(ind.style, {
    position: 'fixed', top: '0', left: '50%', zIndex: '200',
    transform: 'translate(-50%, -48px)', width: '40px', height: '40px',
    borderRadius: '50%', background: 'var(--surface, #1a1d2e)',
    border: '1px solid var(--border, #3a3f63)', color: 'var(--accent, #9ba1ff)',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    boxShadow: '0 4px 16px rgba(0,0,0,0.4)', pointerEvents: 'none',
    opacity: '0', transition: 'opacity 0.15s',
  })
  document.body.appendChild(ind)
  disposers.push(() => ind.remove())

  const THRESHOLD = 70, MAX = 140, FOLLOW = 0.5
  let startY = 0, pulling = false, dist = 0
  const atTop = () => (window.scrollY || document.documentElement.scrollTop || 0) <= 0
  const reset = (animate) => {
    ind.style.transition = animate ? 'opacity 0.2s, transform 0.25s' : 'none'
    ind.style.opacity = '0'
    ind.style.transform = 'translate(-50%, -48px)'
    if (content) {
      content.style.transition = animate ? 'transform 0.25s cubic-bezier(0.2,0.8,0.2,1)' : 'none'
      content.style.transform = ''
    }
  }
  const onStart = e => {
    if (e.touches.length !== 1 || !atTop()) { pulling = false; return }
    startY = e.touches[0].clientY; pulling = true; dist = 0
  }
  const onMove = e => {
    if (!pulling) return
    dist = e.touches[0].clientY - startY
    if (dist <= 0 || !atTop()) { pulling = false; reset(true); return }
    e.preventDefault()
    const pull = Math.min(dist, MAX)
    const ratio = Math.min(pull / THRESHOLD, 1)
    const rot = ratio * 270
    if (content) { content.style.transition = 'none'; content.style.transform = `translateY(${pull * FOLLOW}px)` }
    ind.style.transition = 'none'
    ind.style.opacity = String(ratio)
    ind.style.transform = `translate(-50%, ${-48 + pull * FOLLOW + 8}px) rotate(${rot}deg)`
  }
  const release = () => {
    if (!pulling) return
    pulling = false
    if (dist >= THRESHOLD) {
      ind.style.transition = 'opacity 0.2s, transform 0.2s'
      ind.style.opacity = '1'
      ind.style.transform = 'translate(-50%, 24px) rotate(270deg)'
      ctx.hardReload()
    } else {
      reset(true)
    }
  }
  addEventListener('touchstart', onStart,  { passive: true })
  addEventListener('touchmove',  onMove,   { passive: false })
  addEventListener('touchend',   release,  { passive: true })
  addEventListener('touchcancel', release, { passive: true })
  disposers.push(() => {
    removeEventListener('touchstart', onStart)
    removeEventListener('touchmove', onMove)
    removeEventListener('touchend', release)
    removeEventListener('touchcancel', release)
  })

  // The "Reload" button (cache cleared).
  const reloadBtn = root.querySelector('#hard-reload-btn')
  if (reloadBtn) reloadBtn.addEventListener('click', ctx.hardReload)

  // Replaces the <pre><code> blocks with read-only CM6 editors.
  const canvas = document.getElementById('canvas')   // the SHARED canvas, owned by the shell
  root.querySelectorAll('section pre').forEach(pre => {
    const code = pre.querySelector('code')
    if (!code) return
    const text = code.textContent.trim()
    if (!text) return

    const isRunnable = !pre.hasAttribute('data-no-run') &&
                       !pre.closest('.two-col') &&
                       text.length >= 15 &&
                       !text.includes('source .ol')

    const wrap = document.createElement('div')
    wrap.className = 'cm-static-wrap'
    if (pre.closest('.two-col')) wrap.style.margin = '0'

    editors.push(makeStaticEditor(wrap, text))

    const actions = document.createElement('div')
    actions.className = 'code-actions'
    wrap.appendChild(actions)
    actions.appendChild(makeCopyBtn(() => text))

    let outDiv = null
    if (isRunnable) {
      outDiv = document.createElement('div')
      outDiv.className     = 'inline-output'
      outDiv.style.display = 'none'

      const runBtn = document.createElement('button')
      runBtn.className = 'code-btn run'
      runBtn.title     = 'Run'
      runBtn.innerHTML = ICONS.run
      runBtn.addEventListener('click', () => {
        if (!ollin) {
          outDiv.textContent   = 'Loading the runtime…'
          outDiv.className     = 'inline-output wait'
          outDiv.style.display = 'block'
          return
        }
        canvas.style.display = 'none'
        // Shared execution: it handles try/catch, graphics frame errors and a top-level error
        // arising after the canvas is open.
        Run.runProgram(ollin, text, canvas, {
          onRunning: () => {                       // a graphics program: the canvas goes under the block
            outDiv.style.display = 'none'
            canvas.style.maxWidth = '100%'
            canvas.style.borderRadius = '6px'
            canvas.style.margin = '10px 0'
            wrap.after(canvas)
          },
          onOutput: (out) => {
            outDiv.style.display = 'block'
            if (!out || out === '') {
              outDiv.textContent = '(no output)'
              outDiv.className   = 'inline-output empty'
            } else {
              outDiv.textContent = out
              outDiv.className   = 'inline-output ok'
            }
          },
          onError: (msg) => {
            outDiv.style.display = 'block'
            outDiv.textContent   = msg
            outDiv.className     = 'inline-output err'
          },
        })
      })
      actions.appendChild(runBtn)
    }

    pre.replaceWith(wrap)
    if (outDiv) wrap.after(outDiv)
  })

  // Destroy the CM6 editors (which removes their global observers and listeners, so there is no
  // leak on every revisit), pause the raylib loop (a graphics snippet may have started it) and
  // unhook the frame-error handler.
  disposers.push(() => {
    for (const ed of editors) {
      try { ed.destroy() } catch (_) {}
    }
    try { ollin && ollin.pauseMainLoop() } catch (_) {}
    window.__ollinFrameError = undefined
  })

  // Cleanup, called by the router before another view is mounted.
  return () => { for (const d of disposers) d() }
}
