// Vue TUTORIEL — logique d'initialisation, appelée par app.js après le montage
// du fragment views/tutoriel.html dans #view.
//   init(ctx) → cleanup()    (ctx = { root, getOllin, hardReload, navigate })
// `root`      : élément #view où le fragment est monté (portée des querySelector)
// `getOllin()`: promesse du module WASM PARTAGÉ (une seule instance pour la SPA)
// `hardReload`: rechargement cache-vidé (bouton « Recharger » / pull-to-refresh)
import {
  EditorState,
  EditorView, lineNumbers,
  syntaxHighlighting,
} from '../vendor/codemirror.js'
import { CODE_DISPLAY } from '../cm-shared.js'
import { ollinLang, ollinHighlight } from '../cm-lang.js'

// ── Thème éditeur (blocs read-only du tutoriel) ─────────────────────────────
const ollinTheme = EditorView.theme({
  '&': { background: '#1a1d2e', color: '#c9d1e0', border: '1px solid #2e3150', borderRadius: '8px', fontSize: 'var(--code-size)' },
  '.cm-scroller': { fontFamily: "'JetBrains Mono','Fira Code','Cascadia Code',Consolas,monospace", lineHeight: '1.65', overflow: 'auto', fontSize: 'var(--code-size)' },
  '.cm-content': { padding: '14px 0', caretColor: '#7c83ff', fontSize: 'var(--code-size)' },
  ...CODE_DISPLAY,
  '.cm-gutters': { background: '#1a1d2e', color: '#3d4463', border: 'none', borderRight: '1px solid #2e3150', borderRadius: '8px 0 0 8px' },
  '.cm-activeLine': { background: 'rgba(255,255,255,0.03)' },
  '.cm-activeLineGutter': { background: 'rgba(255,255,255,0.03)', color: '#7c85a2' },
  '&.cm-focused': { outline: 'none', borderColor: '#7c83ff' },
  '&.cm-focused .cm-cursor': { borderLeftColor: '#7c83ff', borderLeftWidth: '2px' },
  '.cm-selectionBackground': { background: 'rgba(255,255,255,0.18) !important' },
  '&.cm-focused .cm-selectionBackground': { background: 'rgba(255,255,255,0.25) !important' },
  '.cm-content[contenteditable="false"]': { cursor: 'default' },
})

const BASE_EXT = [ollinLang, syntaxHighlighting(ollinHighlight), lineNumbers(), ollinTheme, EditorView.lineWrapping]

function makeStaticEditor(parent, code) {
  return new EditorView({
    state: EditorState.create({ doc: code, extensions: [...BASE_EXT, EditorView.editable.of(false), EditorState.readOnly.of(true)] }),
    parent,
  })
}

// ── Icônes SVG ──────────────────────────────────────────────────────────────
const ICON_RUN  = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="12" height="12" fill="currentColor" aria-hidden="true"><path d="M3 2l11 6-11 6V2z"/></svg>'
const ICON_COPY = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><rect x="5.5" y="5.5" width="9" height="9" rx="1.5"/><path d="M10.5 5.5V3a1 1 0 00-1-1H3a1 1 0 00-1 1v7a1 1 0 001 1h2.5"/></svg>'
const ICON_OK   = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M3 8l4 4 6-6"/></svg>'

function makeCopyBtn(getText) {
  const btn = document.createElement('button')
  btn.className = 'code-btn copy'
  btn.title     = 'Copier'
  btn.innerHTML = ICON_COPY
  btn.addEventListener('click', () => {
    navigator.clipboard.writeText(getText()).then(() => {
      btn.innerHTML         = ICON_OK
      btn.style.color       = '#4ade80'
      btn.style.borderColor = '#4ade80'
      setTimeout(() => { btn.innerHTML = ICON_COPY; btn.style.color = ''; btn.style.borderColor = '' }, 1500)
    })
  })
  return btn
}

export function init(ctx) {
  const root = ctx.root
  const disposers = []          // nettoyage au démontage de la vue

  // Le runtime WASM est PARTAGÉ (chargé une fois par app.js). On le « réchauffe »
  // dès l'entrée dans la vue ; les boutons Exécuter l'attendent s'il n'est pas prêt.
  let ollin = null
  ctx.getOllin().then(m => { ollin = m }).catch(err => console.error('WASM init:', err))

  // ── Hamburger (mobile) ────────────────────────────────────────────────────
  const ham      = root.querySelector('#ham')
  const navEl    = root.querySelector('#nav')
  const backdrop = root.querySelector('#backdrop')
  if (ham && navEl && backdrop) {
    const closeNav = () => { navEl.classList.remove('open'); backdrop.classList.remove('visible'); ham.classList.remove('open') }
    const openNav  = () => { navEl.classList.add('open'); backdrop.classList.add('visible'); ham.classList.add('open') }
    ham.addEventListener('click', () => navEl.classList.contains('open') ? closeNav() : openNav())
    backdrop.addEventListener('click', closeNav)
    // Un clic sur un lien de section (ou de vue) referme le menu.
    navEl.querySelectorAll('a').forEach(a => a.addEventListener('click', closeNav))
  }

  // ── Nav active au défilement ──────────────────────────────────────────────
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

  // ── Pull-to-refresh (mobile) ──────────────────────────────────────────────
  // Tirer la page vers le bas en étant tout en haut → rechargement cache-vidé.
  const content = root.querySelector('main')
  const ind = document.createElement('div')
  ind.id = 'ptr-indicator'
  ind.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-2.64-6.36"/><path d="M21 3v6h-6"/></svg>'
  Object.assign(ind.style, {
    position: 'fixed', top: '0', left: '50%', zIndex: '200',
    transform: 'translate(-50%, -48px)', width: '40px', height: '40px',
    borderRadius: '50%', background: 'var(--surface, #1a1d2e)',
    border: '1px solid var(--border, #2e3150)', color: 'var(--accent, #7c83ff)',
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

  // ── Bouton « Recharger » (cache-vidé) ─────────────────────────────────────
  const reloadBtn = root.querySelector('#hard-reload-btn')
  if (reloadBtn) reloadBtn.addEventListener('click', ctx.hardReload)

  // ── Remplace les blocs <pre><code> par des éditeurs CM6 read-only ─────────
  const canvas = document.getElementById('canvas')   // canvas PARTAGÉ (shell)
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

    makeStaticEditor(wrap, text)

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
      runBtn.title     = 'Exécuter'
      runBtn.innerHTML = ICON_RUN
      runBtn.addEventListener('click', () => {
        if (!ollin) {
          outDiv.textContent   = 'Runtime en cours de chargement…'
          outDiv.className     = 'inline-output wait'
          outDiv.style.display = 'block'
          return
        }
        canvas.style.display = 'none'
        const out = ollin.execute(text)
        if (canvas.style.display === 'block') {
          outDiv.style.display = 'none'
          canvas.style.maxWidth = '100%'
          canvas.style.borderRadius = '6px'
          canvas.style.margin = '10px 0'
          wrap.after(canvas)
          return
        }
        outDiv.style.display = 'block'
        if (!out || out === '') {
          outDiv.textContent = '(aucune sortie)'
          outDiv.className   = 'inline-output empty'
        } else if (out.startsWith('error:')) {
          outDiv.textContent = out
          outDiv.className   = 'inline-output err'
        } else {
          outDiv.textContent = out
          outDiv.className   = 'inline-output ok'
        }
      })
      actions.appendChild(runBtn)
    }

    pre.replaceWith(wrap)
    if (outDiv) wrap.after(outDiv)
  })

  // Nettoyage appelé par le routeur avant de monter une autre vue.
  return () => { for (const d of disposers) d() }
}
