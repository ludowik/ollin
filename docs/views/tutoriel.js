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
import { CODE_DISPLAY, CODE_THEME_BASE, ICONS } from '../cm-shared.js'
import { ollinLang, ollinHighlight } from '../cm-lang.js'

// ── Thème éditeur (blocs read-only du tutoriel) ─────────────────────────────
const ollinTheme = EditorView.theme({
  '&': { background: '#1a1d2e', color: '#c9d1e0', border: '1px solid #2e3150', borderRadius: '8px', fontSize: 'var(--code-size)' },
  '.cm-scroller': { fontFamily: "'JetBrains Mono','Fira Code','Cascadia Code',Consolas,monospace", lineHeight: '1.65', overflow: 'auto', fontSize: 'var(--code-size)' },
  '.cm-content': { padding: '14px 0', caretColor: '#7c83ff', fontSize: 'var(--code-size)' },
  ...CODE_DISPLAY,
  ...CODE_THEME_BASE,   // ligne active, curseur, sélection (partagés)
  '.cm-gutters': { background: '#1a1d2e', color: '#3d4463', border: 'none', borderRight: '1px solid #2e3150', borderRadius: '8px 0 0 8px' },
  '&.cm-focused': { outline: 'none', borderColor: '#7c83ff' },
  '.cm-content[contenteditable="false"]': { cursor: 'default' },
})

const BASE_EXT = [ollinLang, syntaxHighlighting(ollinHighlight), lineNumbers(), ollinTheme, EditorView.lineWrapping]

function makeStaticEditor(parent, code) {
  return new EditorView({
    state: EditorState.create({ doc: code, extensions: [...BASE_EXT, EditorView.editable.of(false), EditorState.readOnly.of(true)] }),
    parent,
  })
}

// Icônes SVG (run/copy/ok) : partagées via cm-shared.js.

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
  const disposers = []          // nettoyage au démontage de la vue
  const editors   = []          // éditeurs CM6 statiques créés (à détruire au démontage)

  // Exécution PARTAGÉE (pg-run.js) : mêmes préchargement/gestion d'erreurs que
  // le playground et le mode autonome (try/catch, erreurs de frame graphique).
  const Run = await import('../pg-run.js?v=' + ctx.v)

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

  // ── Mémoriser la position de lecture (restaurée au refresh) ───────────────
  // Seule une entrée SANS ancre explicite (#/tutoriel nu, ou refresh) restaure
  // cette position — un lien de section (#intro, #for…) garde la priorité.
  const SCROLL_KEY = 'ollin-tutoriel-scrollY'
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
      // Deux rAF : laisse le temps aux éditeurs CM6 (montés plus bas) de fixer
      // la hauteur finale du contenu avant de calculer le scroll cible.
      requestAnimationFrame(() => requestAnimationFrame(() => window.scrollTo(0, savedY)))
    }
  }

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
      runBtn.title     = 'Exécuter'
      runBtn.innerHTML = ICONS.run
      runBtn.addEventListener('click', () => {
        if (!ollin) {
          outDiv.textContent   = 'Runtime en cours de chargement…'
          outDiv.className     = 'inline-output wait'
          outDiv.style.display = 'block'
          return
        }
        canvas.style.display = 'none'
        // Exécution partagée : gère try/catch, erreurs de frame graphique et
        // erreur haut-niveau survenant après ouverture du canvas.
        Run.runProgram(ollin, text, canvas, {
          onRunning: () => {                       // programme graphique : canvas sous le bloc
            outDiv.style.display = 'none'
            canvas.style.maxWidth = '100%'
            canvas.style.borderRadius = '6px'
            canvas.style.margin = '10px 0'
            wrap.after(canvas)
          },
          onOutput: (out) => {
            outDiv.style.display = 'block'
            if (!out || out === '') {
              outDiv.textContent = '(aucune sortie)'
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

  // Détruire les éditeurs CM6 (retire leurs observers/listeners globaux → pas
  // de fuite à chaque re-visite), mettre la boucle raylib en pause (un snippet
  // graphique a pu la lancer) et couper le hook d'erreur de frame.
  disposers.push(() => {
    for (const ed of editors) {
      try { ed.destroy() } catch (_) {}
    }
    try { ollin && ollin.pauseMainLoop() } catch (_) {}
    window.__ollinFrameError = undefined
  })

  // Nettoyage appelé par le routeur avant de monter une autre vue.
  return () => { for (const d of disposers) d() }
}
