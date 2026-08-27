// PLAYGROUND view — init(ctx), called by app.js once the fragment is mounted.
//   ctx = { root, getOllin, hardReload, navigate }
// getOllin() gives the SHARED WASM runtime, one instance for the whole app. The body keeps its
// original indentation (moved here as it was from playground.html, to avoid corrupting the
// multi-line strings during a reindentation).
import {
  EditorState,
  EditorView, lineNumbers, keymap, drawSelection, highlightActiveLine, highlightActiveLineGutter,
  defaultKeymap, historyKeymap, history, indentWithTab,
  syntaxHighlighting, indentUnit, codeFolding, foldGutter, foldKeymap, foldService,
  autocompletion, completionKeymap, acceptCompletion,
  closeBrackets, closeBracketsKeymap,
  search, searchKeymap, highlightSelectionMatches,
} from '../vendor/codemirror.js'
import { CODE_DISPLAY, CODE_THEME_BASE, ICONS } from '../cm-shared.js'
import { ollinLang, ollinHighlight } from '../cm-lang.js'

export async function init(ctx) {
const { getOllin, hardReload } = ctx
const disposers = []   // the global listeners to remove on unmount

// Storage through the abstraction layer (pg-provider): `Store` is the working store (local by
// default), `GH` the remote provider (GitHub by default). Plugging in another backend happens in
// pg-provider.js, with no change to the call sites.
const Prov  = await import('../pg-provider.js?v=' + ctx.v)
const Store = await Prov.getProvider(ctx.v)
const GH    = await Prov.getRemote(ctx.v)
const Run   = await import('../pg-run.js?v=' + ctx.v)   // execution shared with run.html
const Fmt   = await import('../pg-format.js?v=' + ctx.v)   // the on-demand formatter
const { pinToVisualViewport } = await import('../pg-viewport.js?v=' + ctx.v)
const { createRemoteSync } = await import('../pg-sync.js?v=' + ctx.v)

// The remote-save coordinator: every local save of a linked project schedules a deferred GitHub
// push (debounced, single-flight, offline-tolerant). The actual machinery is supplied further
// down (sharedRemotePush and canAutoPush).
const sync = createRemoteSync({
  doPush:  p => sharedRemotePush(p),
  canPush: p => canAutoPush(p),
  onError: (err, p) => onRemoteSyncError(err, p),
})
disposers.push(() => sync.cancel())
// A render-size hint private to this view, cleared on unmount so as not to leak into the #/run
// view (which sets its own, but no residue is left all the same).
disposers.push(() => { window.__ollinRenderW = undefined; window.__ollinRenderH = undefined })

// PHONES only, not tablets or iPads, whose interface stays the desktop one: a coarse pointer AND
// a small screen. The short side separates phones (at most ~430) from iPads (at least 744)
// cleanly, whatever the orientation. Every adaptation tied to the software keyboard is guarded by
// this flag.
const isPhone = !!(window.matchMedia && window.matchMedia('(pointer: coarse)').matches)
             && Math.min(window.screen.width, window.screen.height) < 600

// The toolbar sticks to the top of the VISIBLE area when the mobile keyboard opens; otherwise it
// drifts away and vanishes on iOS. Active for as long as the view is mounted.
if (isPhone) disposers.push(pinToVisualViewport())

// SAMPLE mode: the #/playground/sample/<file> route opens the sample straight from the
// repository (samples/…), with NO copy and no persistence. Editing on screen is free but is not
// saved; a refresh reloads the repository's version. The "Create a project" button forks it on
// demand. (The route parsing is shared, in pg-run.js.)
const exampleFile = Run.sampleFromAnchor(ctx.anchor)

// Ollin syntax: KEYWORDS, BUILTINS, ollinLang and ollinHighlight are imported from cm-lang.js.

const ollinTheme = EditorView.theme({
  // The base size is the BROWSER one (13px). Mobile redefines it (playground.html,
  // @media max-width:640px, 12px, against iOS's zoom).
  '&': { background: '#000000', color: '#dde4ef', fontSize: '13px', height: '100%' },
  '.cm-scroller': { fontFamily: "'JetBrains Mono','Fira Code','Cascadia Code',Consolas,monospace", lineHeight: '1.65' },
  '.cm-content': { padding: '14px 0', caretColor: '#9ba1ff' },
  ...CODE_DISPLAY,   // shared display settings (cm-shared.js)
  '.cm-gutters': { background: '#000000', color: '#5a628a', border: 'none', borderRight: '1px solid #3a3f63' },
  ...CODE_THEME_BASE,   // active line, cursor, selection (shared, cm-shared.js)
  '&.cm-focused': { outline: 'none' },

  /* autocomplete dropdown */
  '.cm-tooltip.cm-tooltip-autocomplete': { background: '#1e2133', border: '1px solid #3a3f5c', borderRadius: '6px', boxShadow: '0 4px 16px rgba(0,0,0,0.5)', padding: '2px 0' },
  '.cm-tooltip-autocomplete > ul': { fontFamily: "'JetBrains Mono','Fira Code',Consolas,monospace", fontSize: '12.5px', maxHeight: '280px' },
  '.cm-tooltip-autocomplete > ul > li': { padding: '3px 10px 3px 6px', color: '#dde4ef', lineHeight: '1.5' },
  '.cm-tooltip-autocomplete > ul > li[aria-selected]': { background: '#2d3259', color: '#ffffff' },
  '.cm-completionLabel': { color: '#dde4ef' },
  '.cm-completionDetail': { color: '#a3adc4', fontStyle: 'italic', marginLeft: '6px' },
  '.cm-completionIcon': { opacity: 0.7, width: '16px', marginRight: '4px' },
  '.cm-completionIcon-keyword': { color: '#569CD6' },
  '.cm-completionIcon-function': { color: '#DCDCAA' },
  '.cm-completionIcon-constant': { color: '#4FC1FF' },
  '.cm-completionIcon-namespace': { color: '#C586C0' },
  '[aria-selected] .cm-completionLabel': { color: '#ffffff' },
  '[aria-selected] .cm-completionDetail': { color: '#a0aabf' },

  /* the search panel (Ctrl+F), tuned to the dark theme */
  // fontSize: inherit makes the whole bar follow the editor's font size (13px in a browser, 12px
  // on mobile), and the field heights follow from it. The width is left at its default.
  '.cm-panels': { background: '#1a1d2e', color: '#dde4ef', fontSize: 'inherit' },
  '.cm-panels.cm-panels-top': { borderBottom: '1px solid #3a3f63' },
  '.cm-search': { padding: '8px' },
  '.cm-search label': { color: '#a3adc4' },
  '.cm-textfield': { background: '#0f1117', color: '#dde4ef', border: '1px solid #3a3f63', borderRadius: '4px', fontSize: 'inherit', padding: '3px 6px' },
  '.cm-button': { background: '#242742', color: '#dde4ef', border: '1px solid #3a3f63', borderRadius: '4px', backgroundImage: 'none', fontSize: 'inherit' },
  '.cm-button:hover': { background: '#2d3259' },
  '.cm-panel.cm-search [name=close]': { color: '#a3adc4', fontSize: '18px', padding: '0 8px' },
})

// Autocompletion.
const kw  = label => ({ label, type: 'keyword' })
const cst = (label, detail) => ({ label, type: 'constant', detail })

// A known function: on acceptance it inserts the call with its base parameters PRE-FILLED
// (circle becomes "circle(x, y, radius)"), the parameter list being selected so it can be
// replaced straight away. With no parameter it inserts "name()", the cursor after the bracket.
// The parameters are taken from the signature (detail).
const fn = (label, detail) => {
  const mo = detail && detail.match(/\(([^]*)\)/)
  let params = mo ? mo[1].trim() : ''
  if (params === '...') params = ''            // varargs give empty brackets
  return {
    label, type: 'function', detail,
    apply: (view, c, from, to) => {
      const name = c.label
      const insert = `${name}(${params})`
      const open = from + name.length + 1
      view.dispatch({
        changes: { from, to, insert },
        selection: params ? { anchor: open, head: open + params.length }   // the parameters are selected
                          : { anchor: from + insert.length },              // the cursor lands after the ()
      })
    },
  }
}

// "func" inserts only "func" and a space, the cursor after it, ready for the name to be typed.
// The complete skeleton (parameters, body, end) is produced on acceptance of a known function
// NAME, and never doubles the brackets.
const AC_FUNC = {
  label: 'func', type: 'keyword', detail: 'define a function',
  apply: (view, c, from, to) => {
    view.dispatch({ changes: { from, to, insert: 'func ' }, selection: { anchor: from + 5 } })
  },
}

const AC_KEYWORDS = [
  'var','global','const','if','then','else','elseif','end',
  'while','do','for','in','return','break','true','false','nil',
  'try','catch','throw','class','extends','super','self','import','as',
  'or','and','not','switch','case','default',
].map(kw)

const AC_BUILTINS = [
  fn('print',  'print(...)'),    fn('printf', 'printf(fmt, ...)'),
  fn('assert', 'assert(cond [, msg])'), fn('time', 'time() → float'),
  fn('typeof', 'typeof(v) → string'),   fn('Color', 'Color(grey | r, g, b [, a])'),
  fn('len',    'len(v) → int'),         fn('mem',    'mem() → int (bytes used)'),
]

// The globals injected by the engine, available without a declaration (see CLAUDE.md).
const glob = (label, detail) => ({ label, type: 'variable', detail })
const AC_GLOBALS = [
  glob('deltaTime',   'engine — seconds since the previous frame'),
  glob('elapsedTime', 'engine — seconds since the start'),
  glob('W',  'engine — the render area width'),
  glob('H',  'engine — the render area height'),
  glob('CW', 'engine — centre X (W / 2)'),
  glob('CH', 'engine — centre Y (H / 2)'),
]

// The lifecycle hooks the engine calls, inserted as a COMPLETE skeleton (func … end), the "func"
// not being repeated when it is already typed. The cursor lands in the body, on a new indented
// line. It avoids typos.
function lifecycle(name, params, detail) {
  return {
    label: name, type: 'function', detail,
    apply: (view, c, from, to) => {
      const before = view.state.doc.sliceString(view.state.doc.lineAt(from).from, from)
      const prefix = /\bfunc\s+\S*$/.test(before) ? '' : 'func '   // do not repeat "func"
      const head = `${prefix}${name}(${params})\n    `
      view.dispatch({
        changes: { from, to, insert: head + '\nend' },
        selection: { anchor: from + head.length },   // the cursor lands in the indented body
      })
    },
  }
}
const AC_LIFECYCLE = [
  lifecycle('setup',  '',   'engine — once at startup'),
  lifecycle('update', 'dt', 'engine — logic, every frame'),
  lifecycle('draw',   '',   'engine — rendering, every frame'),
]

const MODULE_MEMBERS = {
  math: [
    cst('math.PI','3.14159…'), cst('math.TAU','6.28318…'), cst('math.E','2.71828…'), cst('math.INF','Infinity'),
    fn('math.abs','abs(x)'),       fn('math.sign','sign(x)'),      fn('math.floor','floor(x)'),
    fn('math.ceil','ceil(x)'),     fn('math.round','round(x)'),    fn('math.trunc','trunc(x)'),
    fn('math.sqrt','sqrt(x)'),     fn('math.pow','pow(x,n)'),      fn('math.clamp','clamp(x,lo,hi)'),
    fn('math.min','min(...)'),     fn('math.max','max(...)'),       fn('math.map','map(x,ilo,ihi,olo,ohi)'),
    fn('math.exp','exp(x)'),       fn('math.log','log(x)'),        fn('math.log2','log2(x)'),
    fn('math.log10','log10(x)'),   fn('math.logn','logn(x,n)'),
    fn('math.frac','frac(x)'),     fn('math.noise','noise(x[,y[,z]])'), fn('math.noiseSeed','noiseSeed(n)'),
    fn('math.sin','sin(x)'),       fn('math.cos','cos(x)'),        fn('math.tan','tan(x)'),
    fn('math.asin','asin(x)'),     fn('math.acos','acos(x)'),      fn('math.atan','atan(x)'),
    fn('math.atan2','atan2(y,x)'),
    fn('math.deg','deg(rad)'),      fn('math.rad','rad(deg)'),
    fn('math.isNan','isNan(x)'), fn('math.isInf','isInf(x)'),
    fn('math.rand','rand([lo,hi])'), fn('math.randInt','randInt([lo,]hi)'), fn('math.seed','seed(n)'),
  ],
  graphics: [
    fn('graphics.canvas','canvas(w,h[,title])'),   fn('graphics.run','run(callback)'),
    fn('graphics.clear','clear([color]) — alpha<1 = fade'),
    fn('graphics.blendMode','blendMode(mode) — "add"/blend.ADD…'),
    fn('graphics.strokeSize','strokeSize(n)'),     fn('graphics.stroke','stroke([color]|r,g,b)'),
    fn('graphics.noStroke','noStroke()'),
    fn('graphics.fill','fill([color])'),           fn('graphics.noFill','noFill()'),
    fn('graphics.tint','tint([color])'),           fn('graphics.noTint','noTint()'),
    fn('graphics.beginDraw','beginDraw()'),      fn('graphics.endDraw','endDraw()'),
    fn('graphics.screenshot','screenshot(path)'),
    fn('graphics.line','line(x1,y1,x2,y2)'),       fn('graphics.rect','rect(x,y,w,h)'),
    fn('graphics.circle','circle(x,y,r)'),          fn('graphics.ellipse','ellipse(x,y,rx,ry)'),
    fn('graphics.point','point(x,y)'),
    fn('graphics.polygon','polygon(pts)'),          fn('graphics.polyline','polyline(pts)'),
    fn('graphics.push','push()'),                   fn('graphics.pop','pop()'),
    fn('graphics.pushMatrix','pushMatrix()'),       fn('graphics.popMatrix','popMatrix()'),
    fn('graphics.pushStyle','pushStyle()'),         fn('graphics.popStyle','popStyle()'),
    fn('graphics.translate','translate(x,y [,z])'), fn('graphics.rotate','rotate(deg [,ax,ay,az])'),
    fn('graphics.rotateX','rotateX(deg)'),          fn('graphics.rotateY','rotateY(deg)'),
    fn('graphics.rotateZ','rotateZ(deg)'),
    fn('graphics.scale','scale(s | sx,sy | sx,sy,sz)'), fn('graphics.resetTransform','resetTransform()'),
    fn('graphics.sprite','sprite(img,x,y[,w,h])'),
    fn('graphics.text','text(str,x,y,size[,color])'),
    fn('graphics.fps','fps()→int'),                fn('graphics.isOpen','isOpen()→bool'),
    fn('graphics.close','close()'),                fn('graphics.quit','quit()'),
    // 3D.
    fn('graphics.camera','camera(px,py,pz, tx,ty,tz [, fovy])'),
    fn('graphics.begin3d','begin3d(cam)'),         fn('graphics.end3d','end3d()'),
    fn('graphics.grid','grid(slices, spacing)'),
    fn('graphics.cube','cube(x,y,z, w,h,l)'),      fn('graphics.sphere','sphere(x,y,z, r)'),
    fn('graphics.cylinder','cylinder(x,y,z, r, h)'),
    fn('graphics.plane','plane(x,y,z, sx,sz)'),
    fn('graphics.model','model(name)'),            fn('graphics.drawModel','drawModel(handle, x,y,z [, scale])'),
    fn('graphics.modelSize','modelSize(handle)'),  fn('graphics.fitDistance','fitDistance(radius [, fovy])'),
    fn('graphics.inFrustum','inFrustum(x,y,z [, radius])'),
    fn('graphics.beginChunk','beginChunk()'),      fn('graphics.endChunk','endChunk()'),
    fn('graphics.drawChunk','drawChunk(handle)'),  fn('graphics.drawChunkAlpha','drawChunkAlpha(handle)'),
    fn('graphics.freeChunk','freeChunk(handle)'),
    fn('graphics.tileset','tileset(img, cols, rows)'),
    fn('graphics.tiles','tiles(top, side, bottom)'), fn('graphics.tile','tile(t)'),
    fn('graphics.tileAnim','tileAnim(t)'),
    fn('graphics.line3d','line3d(x1,y1,z1, x2,y2,z2)'), fn('graphics.point3d','point3d(x,y,z)'),
    fn('graphics.ambient','ambient(v | couleur)'),
    fn('graphics.light','light("dir"|"point", x,y,z [, couleur]) → Light'),
    fn('graphics.texture','texture(img)'),         fn('graphics.noTexture','noTexture()'),
    // Quaternions.
    fn('graphics.quat','quat() → Quat (identity)'),
    fn('graphics.quatAxis','quatAxis(ax,ay,az, deg) → Quat'),
    fn('graphics.quatEuler','quatEuler(pitch,yaw,roll) → Quat'),
    fn('graphics.rotateq','rotateq(q)'),
  ],
  image: [
    fn('image.load','load(path) → img'),
    fn('image.loadData','loadData(format, base64) → img'),
    fn('image.create','create(w, h) → img'),
    fn('image.beginDraw','beginDraw(img)'),
    fn('image.endDraw','endDraw()'),
    fn('image.draw','draw(img, x, y [, w, h [, tint]])'),
    fn('image.unload','unload(img)'),
    fn('image.setPixel','setPixel(img, x, y, color)'),
    fn('image.getPixel','getPixel(img, x, y) → r, g, b, a'),
    fn('image.beginPixels','beginPixels(img)'),
    fn('image.endPixels','endPixels(img)'),
    fn('image.mapPixel','mapPixel(img, f(x,y,r,g,b,a) → r,g,b,a)'),
  ],
  colors: [
    cst('colors.BLACK',''),   cst('colors.WHITE',''),  cst('colors.RED',''),
    cst('colors.GREEN',''),   cst('colors.BLUE',''),   cst('colors.YELLOW',''),
    cst('colors.GRAY',''),    cst('colors.ORANGE',''), cst('colors.PINK',''),
    cst('colors.PURPLE',''),  cst('colors.BROWN',''),  cst('colors.DARKGRAY',''),
    cst('colors.SKYBLUE',''), cst('colors.LIME',''),   cst('colors.MAGENTA',''),
  ],
  blend: [
    cst('blend.ALPHA','normal blending (default)'), cst('blend.ADD','additive (glow)'),
    cst('blend.MULTIPLY','multiplied'),            cst('blend.ADD_COLORS','sum of the colours'),
    cst('blend.SUBTRACT','subtractive'),           cst('blend.PREMULTIPLY','premultiplied alpha'),
  ],
  Color: [
    fn('Color.random','random() → a random colour'),
  ],
  string: [
    fn('string.len','len(s) → int'),
    fn('string.upper','upper(s)'), fn('string.lower','lower(s)'), fn('string.trim','trim(s[,chars])'),
    fn('string.ltrim','ltrim(s[,chars])'), fn('string.rtrim','rtrim(s[,chars])'),
    fn('string.char','char(s,i)'), fn('string.substr','substr(s,start[,len])'),
  ],
  window: [
    cst('window.width','the render area width (px)'),
    cst('window.height','the render area height (px)'),
  ],
  keyboard: [
    fn('keyboard.keypressed','keypressed(key) — to be defined: called on a press'),
    fn('keyboard.keyrelease','keyrelease(key) — to be defined: called on a release'),
  ],
  mouse: [
    fn('mouse.pressed','pressed(x,y) — to be defined: called on a click'),
    fn('mouse.released','released(x,y) — to be defined: on a release'),
    fn('mouse.moved','moved(x,y) — to be defined: on a move'),
    fn('mouse.scrolled','scrolled(x,y,dx,dy) — to be defined: the wheel'),
    fn('mouse.doubleClicked','doubleClicked(x,y) — to be defined: a double click'),
  ],
  touch: [
    fn('touch.began','began(id,x,y) — to be defined: a finger lands'),
    fn('touch.moved','moved(id,x,y) — to be defined: a finger moves'),
    fn('touch.ended','ended(id,x,y) — to be defined: a finger lifts'),
    fn('touch.pinch','pinch(scale,cx,cy) — to be defined: the two-finger zoom'),
    fn('touch.count','count() → int'),
    fn('touch.points','points() → array of {id, x, y}'),
  ],
  data: [
    fn('data.get','get(key [, default]) — a persisted value'),
    fn('data.set','set(key, value) — number/string/boolean'),
    fn('data.has','has(key) → bool'),
    fn('data.delete','delete(key)'),
    fn('data.keys','keys() → array'),
    fn('data.clear','clear() — clears the project scope'),
    cst('data.shared','the scope shared between projects (data.shared.get/set…)'),
  ],
}

// The "start autocompletion" command (CodeMirror's Ctrl-Space binding), reused to reopen the list
// after a module name has been completed.
const startCompletion = (completionKeymap.find(b => b.key === 'Ctrl-Space') || {}).run

function ollinComplete(context) {
  const dotWord = context.matchBefore(/[a-zA-Z_]\w*\.\w*/)
  if (dotWord) {
    const dot    = dotWord.text.indexOf('.')
    const prefix = dotWord.text.slice(0, dot)
    const members = MODULE_MEMBERS[prefix]
    if (members) {
      // We want ALPHABETICAL order — CM otherwise ranks by "fuzzy relevance", which is
      // disconcerting — while KEEPING CM's filtering, hence the bold highlight of the matched
      // substring. The lever: CM sorts on `score + boost`, so we set a dominant `boost`,
      // decreasing with the alphabetical rank. The order becomes alphabetical and the highlight,
      // which comes from CM's filtering, is preserved.
      const opts = members.map(m => ({ ...m, label: m.label.slice(prefix.length + 1) }))
      const rank = new Map(
        [...opts].sort((a, b) => a.label.localeCompare(b.label)).map((o, i) => [o.label, i]))
      return {
        from: dotWord.from + dot + 1,
        options: opts.map(o => ({ ...o, boost: (opts.length - rank.get(o.label)) * 1000 })),
        validFor: /^\w*$/,
      }
    }
    return null
  }
  const word = context.matchBefore(/\w+/)
  if (!word || (word.from === word.to && !context.explicit)) return null
  // Completing a module (math, graphics…) inserts "name." and reopens the list at once on its
  // members, so the dot no longer has to be typed by hand.
  const moduleNames = Object.keys(MODULE_MEMBERS).map(m => ({
    label: m, type: 'namespace',
    apply: (view, c, from, to) => {
      view.dispatch({ changes: { from, to, insert: m + '.' }, selection: { anchor: from + m.length + 1 } })
      if (startCompletion) startCompletion(view)
    },
  }))
  return {
    from: word.from,
    options: [AC_FUNC, ...AC_LIFECYCLE, ...AC_KEYWORDS, ...AC_BUILTINS, ...AC_GLOBALS, ...moduleNames],
    validFor: /^\w*$/,
  }
}

// Block folding. Ollin is a StreamLanguage, with no Lezer tree, so the block bounds are supplied
// through the standard `foldService` facet. A block opens on func, if, while, for, class, try or
// switch and closes on `end`; we track the depth.
const FOLD_OPENERS = /\b(?:func|if|while|for|class|try|switch)\b/g
const FOLD_ENDS    = /\bend\b/g
const countMatches = (s, re) => (s.match(re) || []).length

function ollinFoldRange(state, lineStart) {
  const first = state.doc.lineAt(lineStart)
  const head = first.text.replace(/##.*$/, '')          // ignorer les commentaires
  let depth = countMatches(head, FOLD_OPENERS) - countMatches(head, FOLD_ENDS)
  if (depth <= 0)
    return null                                          // not a net opener, or closed again on the line
  for (let n = first.number + 1; n <= state.doc.lines; n++) {
    const line = state.doc.line(n)
    const body = line.text.replace(/##.*$/, '')
    depth += countMatches(body, FOLD_OPENERS) - countMatches(body, FOLD_ENDS)
    if (depth <= 0) {
      const from = first.to                              // the end of the opening line
      const to = state.doc.line(n - 1).to                // the end of the last line before `end`
      return to > from ? { from, to } : null
    }
  }
  return null
}

// Editor. Its content is driven by the active project (see the "Projects" section below): the
// editor starts empty, then receives the current file after Store.init.
let saveTimer   = null
let autoexecTimer = null  // Auto mode: a deferred restart after the last edit
let loadingFile = false   // true during a programmatic load, so no autosave

// Tab on a PLAIN CURSOR inserts spaces up to the next multiple of four (a tab stop) AT THE
// CURSOR'S POSITION, and does not indent the line. On a selection it returns false, and
// indentWithTab takes over, indenting the block (Shift+Tab outdents).
const softTab = (view) => {
    const state = view.state
    if (state.selection.ranges.some(r => !r.empty))
        return false
    const head = state.selection.main.head
    const col = head - state.doc.lineAt(head).from
    const n = 4 - (col % 4)
    view.dispatch(state.update(state.replaceSelection(' '.repeat(n)), { scrollIntoView: true, userEvent: 'input' }))
    return true
}

// The editor's keymap, kept as a reference: the "during a run" keyboard guard (further down)
// reuses it as it is, so as to delegate to the REAL CodeMirror commands rather than reimplement
// them. Tab accepts a completion when the popup is up, otherwise inserts at the cursor (softTab),
// otherwise — on a selection — indents the block. closeBracketsKeymap comes next: Backspace
// deletes an empty "()" pair in one go.
const editKeymap = [{ key: 'Tab', run: acceptCompletion }, { key: 'Tab', run: softTab }, ...closeBracketsKeymap, ...completionKeymap, indentWithTab, ...defaultKeymap, ...historyKeymap, ...foldKeymap]

// The editor's extensions, reused to recreate a BLANK state on every file load (setEditorText),
// which gives each file its own clean undo history (see setEditorText).
const editorExtensions = [
      ollinLang, syntaxHighlighting(ollinHighlight), lineNumbers(), ollinTheme,
      EditorView.lineWrapping,
      // On iOS Safari the predictive "QuickType" bar intercepts the first Backspace, which then
      // seems to do nothing, and doubles characters. autocorrect, autocapitalize and spellcheck
      // are not always enough to hide it: autocomplete='off' plus inputmode='text' cut it out
      // more firmly.
      EditorView.contentAttributes.of({
        autocorrect: 'off', autocapitalize: 'off', autocomplete: 'off',
        spellcheck: 'false', inputmode: 'text',
      }),
      codeFolding(), foldGutter(), foldService.of(ollinFoldRange),
      history(), drawSelection(), highlightActiveLine(), highlightActiveLineGutter(),
      // CodeMirror's search: Ctrl+F opens the panel and scans the WHOLE document — the model,
      // not the DOM, CM rendering only the visible lines, so the browser's native search missed
      // the rest of the file. highlightSelectionMatches marks the other occurrences of the
      // selected word.
      search({ top: true }), highlightSelectionMatches(),
      keymap.of(editKeymap),
      keymap.of([
        // Alt+Space triggers the autocompletion, a portable alternative to Ctrl+Space, which
        // macOS reserves for the input source.
        { key: 'Alt-Space', run: (v) => (startCompletion ? startCompletion(v) : false) },
        { key: 'Alt-Enter', run: () => { relaunch(); return true } },   // lance / relance
        // Switching file in a multi-file project: Ctrl+Tab is reserved by the browser, hence
        // Alt+PageUp and Alt+PageDown, the web-safe equivalent.
        { key: 'Alt-PageUp', run: () => { cycleFile(-1); return true } },
        { key: 'Alt-PageDown', run: () => { cycleFile(1); return true } },
        { key: 'Escape', run: () => { if (isRunning) { stopExec(); return true } return false } },
        { key: 'Shift-Alt-f', run: () => { doFormat(); return true } },   // reformater
        // F4 goes to the first syntax or runtime error (the link in the output area).
        { key: 'F4', run: () => { if (lastErrorLoc) { gotoError(lastErrorLoc); return true } return false } },
        // A chord (Cmd+K then C or U on a Mac, Ctrl+K then C or U elsewhere): comment and
        // uncomment. Both variants work: Mod released before the second key, or Mod held
        // (Mod+K Mod+C).
        { key: 'Mod-k c', run: (v) => toggleLineComment(v, true) },
        { key: 'Mod-k u', run: (v) => toggleLineComment(v, false) },
        { key: 'Mod-k Mod-c', run: (v) => toggleLineComment(v, true) },
        { key: 'Mod-k Mod-u', run: (v) => toggleLineComment(v, false) },
      ]),
      keymap.of(searchKeymap),   // Ctrl+F (rechercher), Ctrl+G (suivant), etc.
      indentUnit.of('    '),
      // Native auto-pairs: "(" inserts "()", wraps the selection when there is one, and
      // Backspace deletes the empty pair (closeBracketsKeymap).
      closeBrackets(),
      autocompletion({ override: [ollinComplete], activateOnTyping: true }),
      EditorView.updateListener.of(update => {
        if (!update.docChanged || loadingFile) return
        clearTimeout(saveTimer)
        saveTimer = setTimeout(scheduleSave, 500)
        // Auto mode: every edit rearms a countdown, and two seconds of quiet restart the run.
        const chk = document.getElementById('autoexec-chk')
        if (chk && chk.checked) {
          clearTimeout(autoexecTimer)
          autoexecTimer = setTimeout(() => relaunch(), 2000)
        }
      }),
]

// The shortcuts shown by the help popup (F1, or the "Help" button).
// ⚠ SINGLE SOURCE: to be kept in step with the keymaps above (editKeymap, the keymap.of([...])
// holding Alt-Enter, F4, Alt-k…, searchKeymap, foldKeymap, historyKeymap) and with the run
// shortcut handled in onGlobalKeydown.
const SHORTCUTS = [
  { cat: 'Running', items: [
    { keys: ['Alt', '↵'],   desc: 'Run / restart the script' },
    { keys: ['Alt', 'Shift', '↵'], desc: 'Run and turn Auto on (re-runs on every edit)' },
    { keys: ['Esc'],        desc: 'Stop the run under way' },
    { keys: ['F4'],         desc: 'Go to the first error' },
  ]},
  { cat: 'Editing', items: [
    { keys: ['Tab'],            desc: 'Indent at the caret (or accept the completion when the popup is open)' },
    { keys: ['Shift', 'Tab'],   desc: 'Unindent' },
    { keys: ['Alt', 'Space'],  desc: 'Trigger autocompletion' },
    { keys: ['Cmd+K', 'C'], sep: ' then ', desc: 'Comment the selected lines' },
    { keys: ['Cmd+K', 'U'], sep: ' then ', desc: 'Uncomment the selected lines' },
    { keys: ['Alt', 'Shift', 'F'],desc: 'Reformat the code (indentation)' },
    { keys: ['Ctrl', 'Z'],      desc: 'Undo' },
    { keys: ['Ctrl', 'Y'],      desc: 'Redo (or Ctrl+Shift+Z)' },
  ]},
  { cat: 'Search', items: [
    { keys: ['Ctrl', 'F'],      desc: 'Search in the file' },
    { keys: ['Ctrl', 'G'],      desc: 'Next match' },
    { keys: ['Shift', 'Ctrl', 'G'], desc: 'Previous match' },
  ]},
  { cat: 'Folding', items: [
    { keys: ['Ctrl', 'Shift', '['], desc: 'Fold the block' },
    { keys: ['Ctrl', 'Shift', ']'], desc: 'Unfold the block' },
  ]},
  { cat: 'Files', items: [
    { keys: ['Alt', 'Page↑'], desc: 'Previous file (a multi-file project)' },
    { keys: ['Alt', 'Page↓'], desc: 'Next file' },
  ]},
  { cat: 'Help', items: [
    { keys: ['F1'], desc: 'Show / hide this help' },
  ]},
]

const view = new EditorView({
  state: EditorState.create({ doc: '', extensions: editorExtensions }),
  parent: document.getElementById('editor-wrap'),
})

// Comments (add=true) or uncomments (add=false) the lines the selection covers. Ollin's comment
// prefix is '## ' (see grammar.ebnf, line_comment). The insertion and removal happen at the first
// non-blank character, so the indentation is preserved; empty lines are skipped when adding. The
// shortcuts are Alt+K then C or U.
function toggleLineComment(v, add) {
  const { state } = v
  const { from, to } = state.selection.main
  const first = state.doc.lineAt(from).number
  const last = state.doc.lineAt(to).number
  const changes = []
  for (let n = first; n <= last; n++) {
    const line = state.doc.line(n)
    const indent = line.text.length - line.text.trimStart().length
    if (add) {
      if (line.text.trim() === '') continue   // do not comment an empty line
      changes.push({ from: line.from + indent, insert: '## ' })
    } else {
      const rest = line.text.slice(indent)
      const rm = rest.startsWith('## ') ? 3 : rest.startsWith('##') ? 2 : 0
      if (rm) changes.push({ from: line.from + indent, to: line.from + indent + rm })
    }
  }
  if (changes.length) v.dispatch({ changes, userEvent: add ? 'input.comment' : 'delete.uncomment' })
  return true
}

// Backspace and navigation once the graphics runtime is armed.
//
// As soon as a graphics project runs, the raylib runtime (Emscripten's GLFW layer) installs a
// GLOBAL keydown listener (on window, in the capture phase) that calls preventDefault ONLY on
// Backspace and Tab (checked in wasm/ollin.js, GLFW.onKeydown), to stop the browser going back or
// scrolling. That listener stays for as long as the graphics context lives — a plain Stop does not
// remove it. But CodeMirror IGNORES any keydown already defaultPrevented, so in the editor
// Backspace and Tab "no longer do anything".
//
// The counter-measure is a listener registered HERE in the capture phase. As long as the runtime
// has been armed (a graphics program has run) and the editor has focus, Backspace and Tab are
// executed through the REAL CodeMirror commands — the very `editKeymap` the editor uses, hence
// deleteCharBackward, deleteGroupBackward, indentMore and indentLess, acceptCompletion… — and the
// event is then stopped so GLFW never sees it. ONLY those two keys are touched: every other one
// reaches CodeMirror as usual (GLFW does not block them), so no editing behaviour regresses.
//
// The "armed" flag lives at PAGE level (on window), not at view level: the GLFW listener is global
// and is NEVER removed on a change of view (the WASM runtime is shared, there is no CloseWindow).
// A per-view flag would start again at false on every remount, so after a run and a round trip
// between views GLFW would still eat Backspace and Tab while the counter-measure was off — an
// intermittent bug.
const isRuntimeArmed = () => !!window.__ollinGfxKbdArmed
// Runs, for the event `e`, the first binding of `editKeymap` that matches, with the same priority
// semantics as CodeMirror. It handles the Mod and Alt modifiers and the bindings' `shift` variant.
// Returns true when a command acted.
function runEditKeymap(e) {
  for (const b of editKeymap) {
    if (!b.key) continue
    const parts = b.key.split('-')
    if (parts[parts.length - 1] !== e.key) continue
    if ((parts.includes('Mod') || parts.includes('Ctrl') || parts.includes('Cmd')) !== (e.ctrlKey || e.metaKey)) continue
    if (parts.includes('Alt') !== e.altKey) continue
    // CM's semantics: with Shift down we run ONLY b.shift, never b.run; otherwise a binding with
    // no Shift variant (softTab, say) would fire wrongly on Shift+Tab.
    const cmd = e.shiftKey ? b.shift : b.run
    if (cmd && cmd(view)) return true
  }
  return false
}
// The Cmd/Ctrl+K then C or U chord is handled by physical code (e.code), because some browsers or
// layouts may substitute the character (Safari on macOS, for one).
let chordAltKPending = false
const onGlobalKeydown = e => {
  // F1 toggles the help popup (the shortcuts). In the capture phase it works whatever has focus;
  // preventDefault cuts out the browser's own help.
  if (e.key === 'F1') {
    e.preventDefault()
    e.stopImmediatePropagation()
    toggleHelp()
    return
  }
  // Escape closes the Project menu first: its sub-menu, then the menu itself. Before the help and
  // before stopping a run, since the menu is the frontmost thing on screen when it is open.
  if (e.key === 'Escape' && menuIsOpen()) {
    e.preventDefault()
    e.stopImmediatePropagation()
    if (flyIsOpen()) closeFly()
    else closeMenu()
    return
  }
  // Escape closes the help first when it is open, before stopping a run.
  if (e.key === 'Escape' && helpOpen()) {
    e.preventDefault()
    e.stopImmediatePropagation()
    closeHelp()
    return
  }
  // Alt+Shift+Enter runs AND turns Auto mode on, restarting on every edit. Tested BEFORE
  // Alt+Enter, which would match too, altKey being true.
  if (e.key === 'Enter' && e.altKey && e.shiftKey) {
    e.preventDefault()
    e.stopImmediatePropagation()
    const chk = document.getElementById('autoexec-chk')
    const wrap = document.getElementById('autoexec-wrap')
    if (chk) {
      chk.checked = true
      if (wrap) wrap.classList.add('on')
    }
    relaunch()
    return
  }
  // Alt+Enter runs or RESTARTS the execution. It is handled in the capture phase so as to work
  // even when the CANVAS has focus, during a graphics program, and not only in the editor.
  if (e.key === 'Enter' && e.altKey) {
    e.preventDefault()
    e.stopImmediatePropagation()
    relaunch()
    return
  }
  // Escape stops the running program, with focus on the editor OR the canvas.
  if (e.key === 'Escape' && isRunning) {
    e.preventDefault()
    e.stopImmediatePropagation()
    stopExec()
    return
  }
  // The Cmd/Ctrl+K then C or U chord, by physical code, which sidesteps character substitutions.
  if ((e.metaKey || e.ctrlKey) && e.code === 'KeyK' && view.hasFocus) {
    e.preventDefault()
    e.stopImmediatePropagation()
    chordAltKPending = true
    return
  }
  if (chordAltKPending) {
    chordAltKPending = false
    if (view.hasFocus && (e.code === 'KeyC' || e.code === 'KeyU')) {
      e.preventDefault()
      e.stopImmediatePropagation()
      toggleLineComment(view, e.code === 'KeyC')
      return
    }
  }
  if (!isRuntimeArmed() || !view.hasFocus) return
  if (e.key !== 'Backspace' && e.key !== 'Tab') return   // the only keys GLFW eats
  if (runEditKeymap(e)) {
    e.preventDefault()
    e.stopImmediatePropagation()
  }
}
window.addEventListener('keydown', onGlobalKeydown, true)   // in capture, and before GLFW's listener
disposers.push(() => window.removeEventListener('keydown', onGlobalKeydown, true))

// GLFW's keyboard listener is global, on window, so without a guard typing or navigating in the
// editor would also drive a running graphics program (the voxel sample, say). We tell the engine
// (keyboard_module) to ignore the keyboard for as long as the EDITOR has focus; as soon as it
// loses focus, to the canvas or a button, the game receives the keys again.
//
// Resuming editing on a PHONE: re-enabling the keyboard, by focusing the editor, during a running
// program STOPS it, which is a clean return to edit mode, the editor taking the canvas's place —
// otherwise one would be typing "behind" a running program. Phones only: on desktop AND on
// tablets, clicking the editor during a run must not interrupt it, since one may want to read the
// code while watching the canvas.
let isRunning = false   // declared early: onEditorFocus reads it as soon as the init calls view.focus()
const onEditorFocus = () => {
  window.__ollinKbdBlocked = true
  if (isPhone && isRunning) clearAndStop()
}
const onEditorBlur  = () => { window.__ollinKbdBlocked = false }
view.contentDOM.addEventListener('focus', onEditorFocus)
view.contentDOM.addEventListener('blur', onEditorBlur)
window.__ollinKbdBlocked = (document.activeElement === view.contentDOM)
disposers.push(() => {
  view.contentDOM.removeEventListener('focus', onEditorFocus)
  view.contentDOM.removeEventListener('blur', onEditorBlur)
  window.__ollinKbdBlocked = false   // leaving the view: do not block the standalone run
})

// Moving the cursor by a horizontal drag (touch, mobile). The editor wraps lines, so there is no
// horizontal scrolling, and the finger's HORIZONTAL drag moves the cursor instead: one step per
// glyph width dragged, moving LINEARLY through the document, across line ends. A vertical drag
// stays the native scroll.
;(function () {
  const H_THRESHOLD = 8      // px before deciding the gesture's direction
  const dom = view.scrollDOM
  let decided = false, active = false
  let x0 = 0, y0 = 0, head0 = 0

  dom.addEventListener('touchstart', (e) => {
    if (e.touches.length !== 1) return
    x0 = e.touches[0].clientX
    y0 = e.touches[0].clientY
    head0 = view.state.selection.main.head
    decided = false; active = false
  }, { passive: true })

  dom.addEventListener('touchmove', (e) => {
    if (e.touches.length !== 1) return
    const dx = e.touches[0].clientX - x0
    const dy = e.touches[0].clientY - y0
    if (!decided) {
      if (Math.abs(dx) < H_THRESHOLD && Math.abs(dy) < H_THRESHOLD) return
      decided = true
      active = Math.abs(dx) > Math.abs(dy)   // horizontal: we take over; vertical: the native scroll
    }
    if (!active) return
    e.preventDefault()   // we handle it: no native scrolling or selection
    const cw = view.defaultCharacterWidth || 8
    const pos = Math.max(0, Math.min(view.state.doc.length, head0 + Math.round(dx / cw)))
    view.dispatch({ selection: { anchor: pos }, scrollIntoView: true })
  }, { passive: false })

  const end = () => { decided = false; active = false }
  dom.addEventListener('touchend', end, { passive: true })
  dom.addEventListener('touchcancel', end, { passive: true })
})()

// The typing-aid bar (symbols), on touch devices only. It inserts a symbol at the cursor WITHOUT
// stealing the focus, which would close the keyboard. It is shown only on a touch device, when
// the editor has focus.
;(function () {
  const kbar = document.getElementById('kbar')
  if (!kbar) return
  const onDown = (e) => {
    const key = e.target.closest('.kbar-key')
    if (!key) return
    e.preventDefault()   // keeps the editor's focus, so the keyboard stays open
    if (key.hasAttribute('data-run')) {   // ▶ Run (the toolbar is hidden while typing)
      relaunch()
      return
    }
    const move = key.getAttribute('data-move')
    if (move) {
      const forward = move === '1'
      const sel = view.state.selection.main
      // On a selection it collapses to the edge aimed at, as the arrows do; on a cursor it moves by one character.
      const anchor = sel.empty ? view.moveByChar(sel, forward).head : (forward ? sel.to : sel.from)
      view.dispatch({ selection: { anchor }, scrollIntoView: true })
      view.focus()
      return
    }
    const ins  = key.getAttribute('data-ins') || ''
    const back = parseInt(key.getAttribute('data-back') || '0', 10) || 0
    const sel  = view.state.selection.main
    view.dispatch({
      changes: { from: sel.from, to: sel.to, insert: ins },
      selection: { anchor: sel.from + ins.length - back },
      scrollIntoView: true,
    })
    view.focus()
  }
  kbar.addEventListener('pointerdown', onDown)
  disposers.push(() => kbar.removeEventListener('pointerdown', onDown))

  // Shown or hidden on touch devices only, and ONLY when the KEYBOARD really is open. Focus alone
  // is NOT trusted: at startup the init does a programmatic view.focus(), which does NOT open the
  // keyboard on iOS, and the bar must not appear. The keyboard is detected through visualViewport,
  // the visible area shrinking sharply when it opens.
  if (isPhone) {
    const runBtnEl = document.getElementById('run-btn')
    const vv = window.visualViewport
    // An open keyboard means the visible area loses more than 120px against the layout viewport.
    const keyboardOpen = () => (vv ? (window.innerHeight - vv.height > 120) : false)
    const update = () => {
      const editing = document.activeElement === view.contentDOM
      const running = runBtnEl && runBtnEl.classList.contains('running')
      kbar.classList.toggle('show', editing && keyboardOpen() && !running)
      // While typing, with the keyboard up, the toolbar is hidden so the editor gets its height
      // back, which is precious on a small screen. It is restored when the keyboard closes.
      document.body.classList.toggle('kbd-editing', editing && keyboardOpen())
    }
    view.contentDOM.addEventListener('focus', update)
    view.contentDOM.addEventListener('blur', update)
    if (vv) {
      vv.addEventListener('resize', update)
    }
    disposers.push(() => {
      view.contentDOM.removeEventListener('focus', update)
      view.contentDOM.removeEventListener('blur', update)
      if (vv) {
        vv.removeEventListener('resize', update)
      }
      document.body.classList.remove('kbd-editing')   // no toolbar left hidden behind
    })
  }
})()

view.focus()
window.__ollinView = view    // access to the editor for debugging and the console (cleared on unmount)
// (Reopening the last view is handled at the router level, in app.js.)

// Projects and files. The editor edits the CURRENT file of the ACTIVE project. The Project menu
// (a drill-down) and the side file list drive the state. Run is still single-file at this stage:
// it runs the file on display.
const projectBtn   = document.getElementById('project-btn')
const projectLabel = document.getElementById('project-label')
const projectMenu  = document.getElementById('project-menu')
const fileRail     = document.getElementById('file-list')
const ghRailEl     = document.getElementById('gh-rail')
const ghRailBody   = document.getElementById('gh-rail-body')
const newFileBtn   = document.getElementById('new-file-btn')
const resList      = document.getElementById('res-list')
const newResBtn    = document.getElementById('new-res-btn')
const resView      = document.getElementById('res-view')
const editorBox    = document.getElementById('editor-wrap')

let currentProject = null    // objet projet complet
let currentFile    = null    // chemin du fichier ouvert
// The resource DISPLAYED in place of the editor (null means we are editing). Declared here, with
// the state: renderFiles and openFile read it much higher up in the file, and a `let` declared
// after them would expose them to "Cannot access before initialization".
let currentRes     = null
let examples       = []      // [{name, file}] for "New from an example"

// In sample mode the current project is TRANSIENT, loaded from the repository and never
// persisted. All of its files can be seen and navigated, but nothing is written to the database
// and the structure cannot be changed (no creating, renaming or deleting) — "Create a project" is
// the way to edit. A sample IS the TRANSIENT project (the sentinel id), never a record in the
// database. A persistable flag is not to be trusted: it could leak into the database and wrongly
// hide renaming and deletion (Store.init self-repairs that).
const isExample = () => !!(currentProject && currentProject.id === Store.TRANSIENT_ID)

const fileKey = id => 'ollin-pg-file:' + id           // the last file opened, per project
const scripts = p => Object.keys(p.files).filter(f => f !== Store.MANIFEST).sort()

// Shows or hides the structure-CHANGING buttons (＋ file, ＋ resource): hidden in sample mode,
// the transient project not being editable, and visible otherwise.
function setStructuralUI(enabled) {
  newFileBtn.style.display = enabled ? '' : 'none'
  newResBtn.style.display  = enabled ? '' : 'none'
}

function setEditorText(text) {
  loadingFile = true
  // The whole state is recreated, hence a BLANK undo history. Loading a file must not be
  // undoable — Ctrl+Z would otherwise empty the file — and each file has its own history, without
  // which a Ctrl+Z after switching files would bring back the previous file's content. setState
  // replaces the document and the history in one go.
  view.setState(EditorState.create({ doc: text, extensions: editorExtensions }))
  loadingFile = false
}

function flushEditorToFile() {
  if (currentProject && currentFile)
    currentProject.files[currentFile] = view.state.doc.toString()
}

function scheduleSave() {
  if (!currentProject || isExample()) return   // an example is never persisted
  flushEditorToFile()
  persist(currentProject)
}

// The unified save of a change to the current project: it persists locally, at once, THEN
// schedules a deferred remote push when the project is eligible. This single source replaced the
// scattered Store.saveProject calls (typing and structure changes alike), so every change follows
// the same synchronisation path.
function persist(project) {
  project.dirty = true   // a local change, to be pushed (the single sync flag)
  updateSyncBadge()      // a blue badge: local changes to push
  sync.schedule(project) // the deferred remote push, a no-op when not eligible
  return Store.saveProject(project).catch(e => console.error('saveProject', e))
}

// The side file list. The GitHub rail is reduced to an indicator: the repository's name, for
// information. The synchronisation is entirely automatic (the dirty flag), with no manual Push or
// Pull buttons.
function renderGhRail() {
  const p = currentProject
  const show = !!(p && !isExample() && p.remote && p.remote.slug && GH.isConnected() && GH.getRepo())
  ghRailEl.style.display = show ? '' : 'none'
  if (!show) return
  ghRailBody.innerHTML = ''
  const repo = document.createElement('div')
  repo.className = 'gh-repo'
  repo.textContent = p.remote.repo || GH.getRepo()
  repo.title = repo.textContent
  ghRailBody.appendChild(repo)
}

function renderFiles() {
  fileRail.innerHTML = ''
  if (!currentProject) return
  for (const path of scripts(currentProject)) {
    const isEntry = path === currentProject.entry
    const row = document.createElement('div')
    row.className = 'file-item' + (path === currentFile && currentRes === null ? ' active' : '')
    row.title = path
    const label = document.createElement('span')
    label.className = 'file-name'
    label.textContent = path
    if (isEntry) row.classList.add('entry')
    row.appendChild(label)

    if (!isExample()) {   // an example: reading and navigating only, no mutation
      const acts = document.createElement('span')
      acts.className = 'file-acts'
      acts.appendChild(iconBtn(isEntry ? '★' : '☆', isEntry ? 'Entry point' : 'Set as the entry point',
        e => { e.stopPropagation(); setEntry(path) }))
      acts.appendChild(iconBtn('✎', 'Rename', e => { e.stopPropagation(); renameFile(path) }))
      acts.appendChild(iconBtn('🗑', 'Delete', e => { e.stopPropagation(); deleteFile(path) }))
      row.appendChild(acts)
    }

    row.addEventListener('click', () => openFile(path))
    fileRail.appendChild(row)
  }
}

function iconBtn(txt, title, on) {
  const b = document.createElement('button')
  b.className = 'file-act'
  b.textContent = txt
  b.title = title
  b.addEventListener('click', on)
  return b
}

function openFile(path) {
  if (path === currentFile) {
    if (currentRes !== null) showResource(null)   // the same file, but we were leaving a preview
    return
  }
  flushEditorToFile()
  currentFile = path
  setEditorText(currentProject.files[path] ?? '')
  if (!isExample()) localStorage.setItem(fileKey(currentProject.id), path)
  renderGhRail(); renderFiles()
  if (currentRes !== null) {
    showResource(null)   // makes the editor visible, and refreshes both rails
    return
  }
  view.focus()
}

// Switches to the project's previous (dir=-1) or next (dir=+1) file, wrapping around. It works in
// sample mode too, as read-only navigation: openFile persists nothing there.
function cycleFile(dir) {
  if (!currentProject) return
  const list = scripts(currentProject)
  if (list.length < 2) return
  let i = list.indexOf(currentFile)
  if (i < 0) i = 0
  openFile(list[(i + dir + list.length) % list.length])
}

async function newFile() {
  if (!currentProject || isExample()) return   // no editable project (a 404 sample, say)
  let name = prompt('Name of the new file (.ol):', 'new.ol')
  if (!name) return
  name = name.trim()
  if (!/\.ol$/.test(name)) name += '.ol'
  if (currentProject.files[name] !== undefined) { alert('That file already exists.'); return }
  flushEditorToFile()
  currentProject.files[name] = ''
  await persist(currentProject)
  openFile(name)
}

async function renameFile(path) {
  let name = prompt('Rename the file:', path)
  if (!name || name.trim() === path) return
  name = name.trim()
  if (!/\.ol$/.test(name)) name += '.ol'
  if (currentProject.files[name] !== undefined) { alert('That name is already taken.'); return }
  flushEditorToFile()
  currentProject.files[name] = currentProject.files[path]
  delete currentProject.files[path]
  if (currentProject.entry === path) currentProject.entry = name
  if (currentFile === path) currentFile = name
  await persist(currentProject)
  localStorage.setItem(fileKey(currentProject.id), currentFile)
  setEditorText(currentProject.files[currentFile] ?? '')
  renderGhRail(); renderFiles()
}

async function deleteFile(path) {
  if (scripts(currentProject).length <= 1) { alert('A project must keep at least one file.'); return }
  if (!confirm(`Delete "${path}"?`)) return
  delete currentProject.files[path]
  if (currentProject.entry === path) currentProject.entry = scripts(currentProject)[0]
  if (currentFile === path) currentFile = currentProject.entry
  await persist(currentProject)
  setEditorText(currentProject.files[currentFile] ?? '')
  renderGhRail(); renderFiles()
}

async function setEntry(path) {
  currentProject.entry = path
  await persist(currentProject)
  renderGhRail(); renderFiles()
}

// Resources (images, models…).
const IMG_EXT = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']

function resMime(ext) {
  const e = (ext || '').toLowerCase()
  return e === 'jpg' ? 'image/jpeg' : 'image/' + e
}

// Shows the editor (res = null) or the preview of a resource.
function showResource(name) {
  currentRes = name
  const editing = name === null
  editorBox.style.display = editing ? '' : 'none'
  resView.style.display = editing ? 'none' : 'flex'
  resView.innerHTML = ''   // emptied IN BOTH CASES: the image's data URL would otherwise
  renderFiles(); renderResources()   // stay in the DOM after the return to the editor
  if (editing) {
    view.focus()
    return
  }
  const r = (currentProject.resources || {})[name] || {}
  const ext = (r.ext || name.split('.').pop() || '').toLowerCase()
  const bytes = Math.round((r.b64 || '').length * 3 / 4)

  const head = document.createElement('div'); head.className = 'res-head'
  const nm = document.createElement('span'); nm.className = 'res-name'; nm.textContent = name
  const sp = document.createElement('span'); sp.className = 'res-sp'
  const info = document.createElement('span')
  head.append(nm, sp, info)
  const close = document.createElement('button')
  close.className = 'file-act'; close.textContent = '✕'; close.title = 'Back to the editor'
  close.addEventListener('click', () => showResource(null))
  head.appendChild(close)
  resView.appendChild(head)

  if (IMG_EXT.includes(ext)) {
    const frame = document.createElement('div'); frame.className = 'res-frame'
    const img = document.createElement('img')
    img.src = 'data:' + resMime(ext) + ';base64,' + (r.b64 || '')
    // The dimensions are only known once decoded, and the preview fills them in then.
    img.addEventListener('load', () => {
      info.textContent = `${img.naturalWidth} × ${img.naturalHeight} · ${fmtSize(bytes)}`
    })
    img.addEventListener('error', () => { info.textContent = 'unreadable image' })
    frame.appendChild(img)
    resView.appendChild(frame)
  } else {
    info.textContent = fmtSize(bytes)
    const note = document.createElement('div'); note.className = 'res-note'
    note.textContent = ext ? `"${ext}" resource — no preview for this format.`
                           : 'Binary resource — no preview.'
    resView.appendChild(note)
  }
}

function fmtSize(n) {
  return n < 1024 ? n + ' o' : (n / 1024).toFixed(1) + ' Ko'
}

function renderResources() {
  resList.innerHTML = ''
  if (!currentProject) return
  const names = Object.keys(currentProject.resources || {}).sort()
  if (!names.length) {
    const d = document.createElement('div'); d.className = 'rail-empty'; d.textContent = '(none)'
    resList.appendChild(d); return
  }
  for (const name of names) {
    const row = document.createElement('div')
    row.className = 'file-item' + (name === currentRes ? ' active' : ''); row.title = name
    const label = document.createElement('span'); label.className = 'file-name'; label.textContent = name
    row.appendChild(label)
    if (!isExample()) {
      const acts = document.createElement('span'); acts.className = 'file-acts'
      acts.appendChild(iconBtn('✎', 'Rename', e => { e.stopPropagation(); renameResource(name) }))
      acts.appendChild(iconBtn('🗑', 'Delete', e => { e.stopPropagation(); deleteResource(name) }))
      row.appendChild(acts)
    }
    // Clicking the displayed resource again returns to the editor: it toggles.
    row.addEventListener('click', () => showResource(name === currentRes ? null : name))
    resList.appendChild(row)
  }
}

async function renameResource(name) {
  let n = prompt('Rename the resource:', name)
  if (!n || n.trim() === name) return
  n = n.trim()
  if (currentProject.resources[n] !== undefined) { alert('That name is already taken.'); return }
  currentProject.resources[n] = currentProject.resources[name]
  delete currentProject.resources[name]
  const shown = currentRes === name
  await persist(currentProject)
  if (ollin && ollin.preloadImage) {
    const r = currentProject.resources[n]
    ollin.preloadImage(n, r.b64, r.ext)
  }
  if (shown) {
    showResource(n)   // the preview carries the name in its header, so rebuild it
    return
  }
  renderResources()
}

async function deleteResource(name) {
  if (!confirm(`Delete the resource "${name}"?`)) return
  delete currentProject.resources[name]
  await persist(currentProject)
  if (currentRes === name) {
    showResource(null)   // the displayed resource no longer exists
    return
  }
  renderResources()
}


// Loading and switching project.
async function loadProject(id) {
  const p = await Store.getProject(id)
  if (!p) return
  if (isRunning) clearAndStop()   // changing PROJECT means another script, so close the preview
  removeExampleBanner()   // quitte le mode exemple
  setStructuralUI(true)   // a real project, so changes are allowed
  flushEditorToFile()
  currentProject = p
  Store.setActiveId(id)
  railHidden = !localStorage.getItem(railKey(id))
  applyRail()
  const files = scripts(p)
  const last = localStorage.getItem(fileKey(id))
  currentFile = (last && p.files[last] !== undefined) ? last
              : (p.files[p.entry] !== undefined ? p.entry : files[0])
  setEditorText(p.files[currentFile] ?? '')
  projectLabel.textContent = p.name
  renderGhRail(); renderFiles()
  renderResources()
  view.focus()
  // Remote reconciliation on opening: an immediate badge, plus the auto-pull and its guard.
  syncOnOpen(p)   // non bloquant
}

async function switchProject(id) {
  if (currentProject && !isExample()) {       // a sample, being transient, has nothing to save
    flushEditorToFile()                       // pick up the last keystrokes
    await Store.saveProject(currentProject)   // then persist before leaving
  }
  await loadProject(id)
}

// Opens a project from the menu. In SAMPLE mode, with no current project, we leave that mode by
// NAVIGATING (as forkExampleToProject does), which gives a clean remount in project mode and a
// correct URL — a refresh reopens the project rather than the sample. Otherwise it switches in
// place. This fixed a bug: in sample mode, opening or creating a project showed nothing although
// the project really was created, and it only appeared after restarting the app.
async function openProject(id) {
  if (exampleFile) {
    Store.setActiveId(id)
    ctx.navigate('playground')
  } else {
    await switchProject(id)
  }
}

// The Project menu. Two ways of showing a sub-menu, and ONE function builds the contents for
// both: CASCADING beside its row, as a desktop menu does, and on a screen too narrow for a second
// panel, the same list REPLACING the menu's contents, with a back arrow.
const flyMenu = document.getElementById('menu-fly')
let flyRow = null          // the row that opened the flyout, lit while it is open
let flyOpenTimer = null    // the delay before opening on hover, so a mere pass-by does not fire
let flyCloseTimer = null   // the delay before closing, so the pointer can cross the gap

function menuIsOpen() {
  return projectMenu.style.display === 'block'
}
function flyIsOpen() {
  return flyMenu.style.display === 'block'
}
function closeFly() {
  clearTimeout(flyOpenTimer)
  clearTimeout(flyCloseTimer)
  flyMenu.style.display = 'none'
  flyMenu.innerHTML = ''
  if (flyRow) flyRow.classList.remove('menu-open')
  flyRow = null
}
function closeMenu() {
  closeFly()
  projectMenu.style.display = 'none'
  projectBtn.setAttribute('aria-expanded', 'false')
}
function openMenu() {
  renderMenuRoot()
  projectMenu.style.display = 'block'
  projectBtn.setAttribute('aria-expanded', 'true')
}

// Places the flyout to the right of the menu and says whether it FITS; the caller falls back to
// the drill-down when it does not — the case of a phone, where the menu is already 82vw.
//
// Only the right-hand side is tried, and that is not an oversight: the menu hangs from a button at
// the LEFT end of the bar, so whenever the right has no room, the left has even less (the menu's
// own left edge is barely 100 px from the window's). A flip would be a branch that never runs.
function placeFly(row) {
  const m = projectMenu.getBoundingClientRect()
  const r = row.getBoundingClientRect()
  const w = flyMenu.offsetWidth
  const h = flyMenu.offsetHeight
  const edge = 6
  const left = m.right + 4
  if (left + w > window.innerWidth - edge) return false
  // The first item lines up with its row; the panel is then pushed back inside the window, a long
  // list otherwise running off the bottom.
  let top = r.top - 5
  if (top + h > window.innerHeight - edge) top = window.innerHeight - h - edge
  if (top < edge) top = edge
  flyMenu.style.left = left + 'px'
  flyMenu.style.top = top + 'px'
  return true
}

// Opens the flyout for `row`, filling it through `build(panel)`. Returns false when there is no
// room, WITHOUT having shown anything: the caller then drills down instead.
function openFly(row, title, build) {
  clearTimeout(flyCloseTimer)
  if (flyRow === row && flyIsOpen()) return true
  closeFly()
  flyMenu.innerHTML = ''
  // A back arrow even though the parent stays visible beside it: it is the way back on a TOUCH
  // screen, where there is no pointer to move away, and it is the arrow every other sub-menu of
  // this menu carries.
  flyMenu.appendChild(menuHeader(title, closeFly))
  build(flyMenu)
  // Measured while shown but not yet placed: offsetWidth is 0 on a hidden element.
  flyMenu.style.left = '-9999px'
  flyMenu.style.top = '0px'
  flyMenu.style.display = 'block'
  if (!placeFly(row)) {
    flyMenu.style.display = 'none'
    flyMenu.innerHTML = ''
    return false
  }
  flyRow = row
  row.classList.add('menu-open')
  return true
}

// A row that opens a cascading sub-menu: on hover after a short delay, at once on a click — a
// touch screen has no hover. `fallback` is the drill-down, used when the flyout does not fit.
function menuFlyItem(label, title, build, fallback) {
  const row = menuItem(label, true, () => {
    if (!openFly(row, title, build)) fallback()
  })
  row.addEventListener('mouseenter', () => {
    clearTimeout(flyCloseTimer)
    clearTimeout(flyOpenTimer)
    flyOpenTimer = setTimeout(() => openFly(row, title, build), 120)
  })
  row.addEventListener('mouseleave', () => {
    clearTimeout(flyOpenTimer)
    flyCloseTimer = setTimeout(closeFly, 260)
  })
  return row
}
// Entering the flyout cancels the closing the row's mouseleave scheduled; leaving it closes.
flyMenu.addEventListener('mouseenter', () => clearTimeout(flyCloseTimer))
flyMenu.addEventListener('mouseleave', () => { flyCloseTimer = setTimeout(closeFly, 260) })
// Being in `fixed`, the flyout does not follow the menu's own scrolling: it is replaced, and
// dropped when its row has scrolled out of the menu.
projectMenu.addEventListener('scroll', () => {
  if (!flyIsOpen() || !flyRow) return
  const m = projectMenu.getBoundingClientRect()
  const r = flyRow.getBoundingClientRect()
  if (r.bottom < m.top || r.top > m.bottom) closeFly()
  else placeFly(flyRow)
})
function menuItem(label, arrow, on) {
  const b = document.createElement('button')
  b.className = 'menu-item'
  b.innerHTML = `<span>${label}</span>` + (arrow ? '<span class="menu-arrow">›</span>' : '')
  b.addEventListener('click', on)
  return b
}
function menuHeader(text, back) {
  const h = document.createElement('div')
  h.className = 'menu-header'
  if (back) {
    const b = document.createElement('button')
    b.className = 'menu-back'
    b.textContent = '‹'
    b.title = 'Back'
    b.addEventListener('click', back)
    h.appendChild(b)
  }
  const s = document.createElement('span')
  s.textContent = text
  h.appendChild(s)
  return h
}
// A menu entry that opens an external page. A real link rather than a button: no click listener
// to carry, and the browser handles the opening.
function menuLink(label, href) {
  const a = document.createElement('a')
  a.className = 'menu-item'
  a.href = href
  a.target = '_blank'
  a.rel = 'noopener'
  const s = document.createElement('span')
  s.textContent = label
  a.appendChild(s)
  a.addEventListener('click', closeMenu)
  return a
}

function menuSep() {
  const d = document.createElement('div')
  d.className = 'menu-sep'
  return d
}
function menuGroupLabel(text) {
  const d = document.createElement('div')
  d.className = 'menu-group'
  d.textContent = text
  return d
}

function renderMenuRoot() {
  projectMenu.innerHTML = ''
  projectMenu.appendChild(menuHeader('Project: ' + (currentProject ? currentProject.name : '—')))
  projectMenu.appendChild(menuItem('✨ New empty project', false, async () => {
    const name = await askFreeProjectName('Untitled'); if (!name) return
    const p = await Store.createProject(name)
    closeMenu()
    await autoPushNewProject(p)   // with a repository set, it is created on GitHub
    await openProject(p.id)
  }))
  projectMenu.appendChild(menuItem('📂 Open a project', true, renderMenuOpen))
  projectMenu.appendChild(menuItem('📄 Open an example', true, renderMenuExamples))
  // Actions on the CURRENT PROJECT, hidden in sample mode: the project being transient, there is
  // nothing in the database to rename, duplicate or delete.
  if (currentProject && !isExample()) {
    projectMenu.appendChild(menuSep())
    projectMenu.appendChild(menuItem('✎ Rename', false, async () => {
      const name = await askFreeProjectName(currentProject.name, {
        label: 'New name:',
        exclude: { id: currentProject.id, slug: (currentProject.remote && currentProject.remote.slug) || currentProject.id },
      })
      if (!name) return
      flushEditorToFile(); await Store.saveProject(currentProject)
      const p = await Store.renameProject(currentProject.id, name)
      closeMenu(); await loadProject(p.id)
    }))
    projectMenu.appendChild(menuItem('⧉ Duplicate', false, async () => {
      flushEditorToFile(); await Store.saveProject(currentProject)
      const dupName = await askFreeProjectName(currentProject.name + ' (copy)'); if (!dupName) return
      const copy = await Store.createProject(dupName)
      copy.files = { ...currentProject.files }; copy.entry = currentProject.entry
      copy.resources = { ...currentProject.resources }   // duplicate the assets TOO
      delete copy.files[Store.MANIFEST]
      await Store.saveProject(copy)
      closeMenu()
      await autoPushNewProject(copy)   // with a repository set, it is created on GitHub
      await switchProject(copy.id)
    }))
    // A project pushed to GitHub is deleted THERE TOO, the checkbox being ticked: leaving the
    // remote folder behind was not a decision but an omission, and it had consequences — the
    // project came back under "Remote" in the open menu, and its name stayed taken, the free-name
    // check reading the remote list as well. Unticking keeps the GitHub copy, which is the way to
    // free the local space while keeping a backup.
    projectMenu.appendChild(menuItem('🗑 Delete', hasRemote(currentProject), () => {
      if (hasRemote(currentProject)) renderMenuDelete()
      else if (confirm(`Delete the project "${currentProject.name}"?`)) deleteCurrent(false)
    }))
  }

  projectMenu.appendChild(menuSep())
  const ghLabel = GH.isConnected() ? ('🐙 GitHub' + (ghLogin ? ' : @' + ghLogin : '')) : '🐙 GitHub'
  projectMenu.appendChild(menuItem(ghLabel, true, renderMenuGithub))
  projectMenu.appendChild(menuSep())
  projectMenu.appendChild(menuItem('⌨ Keyboard shortcuts (F1)', false, () => { closeMenu(); openHelp() }))
}

// Is this project pushed to a repository we can still reach? Deleting the remote copy is only
// offered then: without a token or a repository there is nothing to delete, and the local delete
// keeps its plain confirmation.
function hasRemote(p) {
  return !!(p && p.remote && p.remote.slug && GH.isConnected() && GH.getRepo())
}

// Deletes the project on display: locally always, and on GitHub when asked. The remote deletion
// comes FIRST: should it fail, the project stays whole on both sides rather than losing its local
// copy and keeping an orphan folder.
async function deleteCurrent(alsoRemote) {
  const gone = currentProject
  if (alsoRemote) {
    setStatus('Deleting on GitHub…')
    const slugs = [gone.id]
    if (gone.remote && gone.remote.slug && gone.remote.slug !== gone.id) slugs.push(gone.remote.slug)
    try {
      await GH.deleteRemoteProject(slugs, `ollin: delete ${gone.name}`)
    } catch (e) {
      setStatus('GitHub: ' + e.message, true, true)
      return false
    }
  }
  await Store.deleteProject(gone.id)
  const list = await Store.listProjects()
  closeMenu()
  if (list.length) await loadProject(list[0].id)
  else { const p = await Store.createProject('Untitled'); await loadProject(p.id) }
  setStatus(alsoRemote ? 'Project deleted, GitHub included ✓' : 'Project deleted locally ✓', true)
  return true
}

// The confirmation for a synchronised project: what is about to be deleted is named, and the
// GitHub copy is included by DEFAULT — which is what one expects of a delete, and what the rest
// of the sync already does (a rename removes the old folder).
function renderMenuDelete() {
  const p = currentProject
  projectMenu.innerHTML = ''
  projectMenu.appendChild(menuHeader('Delete “' + p.name + '”', renderMenuRoot))
  const wrap = document.createElement('div'); wrap.className = 'menu-form'
  const info = document.createElement('div'); info.className = 'menu-info'
  info.innerHTML = 'This project is synchronised with <b>' + (p.remote.repo || 'GitHub')
    + '</b>. Its folder <b>' + p.id + '/</b> will be removed in one commit; the repository\'s history keeps it.'
  const see = document.createElement('label'); see.className = 'menu-check'
  const box = document.createElement('input'); box.type = 'checkbox'; box.checked = true
  see.append(box, document.createTextNode('Delete the GitHub copy too'))
  const btn = document.createElement('button'); btn.className = 'menu-btn'; btn.textContent = 'Delete'
  btn.addEventListener('click', async () => {
    btn.disabled = true
    if (!await deleteCurrent(box.checked)) btn.disabled = false
  })
  wrap.append(info, see, btn)
  projectMenu.appendChild(wrap)
}

// The GitHub sub-menu gathers every feature (connecting, the repository, pushing and pulling,
// opening, disconnecting). It is reached from "🐙 GitHub" at the root.
function renderMenuGithub() {
  projectMenu.innerHTML = ''
  if (!GH.isConnected()) {
    projectMenu.appendChild(menuHeader('GitHub', renderMenuRoot))
    projectMenu.appendChild(menuItem('🔗 Sign in to GitHub', true, renderMenuConnect))
    return
  }
  const hdr = menuHeader('GitHub' + (ghLogin ? ' : @' + ghLogin : ''), renderMenuRoot)
  projectMenu.appendChild(hdr)
  if (!ghLogin) {
    ghLogin = GH.knownLogin()   // already resolved by a push or pull: no extra request
  }
  if (!ghLogin) {
    const span = hdr.querySelector('span')
    GH.getUser().then(u => { ghLogin = u.login; if (span) span.textContent = 'GitHub : @' + u.login }).catch(() => {})
  }
  // The repository AND the token sit behind the SAME entry: they are two halves of one setting (a
  // token is only good for the repository it grants access to), and a fine-grained token expires,
  // so it must be replaceable without going through a disconnection.
  projectMenu.appendChild(menuItem('GitHub repo', false, renderMenuConnect))
  projectMenu.appendChild(menuLink('Renew the token', TOKEN_URL))
  projectMenu.appendChild(menuItem('Sign out', false, () => { GH.clearToken(); ghLogin = null; renderMenuGithub() }))
}

// A UNIFIED "Open a project" menu: local ones (🖥 unlinked), synchronised ones (🔄 linked) and
// remote-only ones (☁ present on GitHub, absent locally). The first two sections are computed
// without the network — the link being the local remote.slug — and so are shown at once; the
// remote section is merged in in the background.
async function renderMenuOpen() {
  const local = await Store.listProjects()
  projectMenu.innerHTML = ''
  projectMenu.appendChild(menuHeader('Open a project', renderMenuRoot))
  const body = document.createElement('div')
  projectMenu.appendChild(body)

  const localSlugs = new Set(local.map(p => (p.remote && p.remote.slug) || p.id))
  const isLinked = p => !!(p.remote && p.remote.slug)
  const nameOf = p => ((currentProject && p.id === currentProject.id) ? '✓ ' : '') + p.name
  const openLocal = id => async () => {
    closeMenu()
    if (!currentProject || id !== currentProject.id) await openProject(id)
  }

  // Rebuilds the body: only the non-empty sections, plus the remote footer with the network state.
  const render = (remoteOnly, footer) => {
    if (!projectMenu.contains(body)) return   // the menu changed meanwhile
    body.innerHTML = ''
    const group = (label, items, mk) => {
      if (!items.length) return
      body.appendChild(menuGroupLabel(label))
      for (const it of items) body.appendChild(mk(it))
    }
    group('🖥 Local', local.filter(p => !isLinked(p)), p => menuItem(nameOf(p), false, openLocal(p.id)))
    group('🔄 Synchronised', local.filter(isLinked), p => menuItem(nameOf(p), false, openLocal(p.id)))
    group('☁ Remote', remoteOnly, r => menuItem(r.name, false, () => openRemoteProject(r.slug)))
    if (footer)
      body.appendChild(footer)
    if (!body.childNodes.length) {
      const d = document.createElement('div'); d.className = 'menu-empty'; d.textContent = 'No project.'
      body.appendChild(d)
    }
  }

  // The remote footer, according to the connection and network state.
  const info = txt => { const d = document.createElement('div'); d.className = 'menu-empty'; d.textContent = txt; return d }
  if (!GH.isConnected()) {
    render([], menuItem('🔗 Sign in to GitHub', true, renderMenuConnect))
    return
  }
  if (!GH.getRepo()) {
    render([], info('No GitHub repository set (the 🐙 GitHub menu).'))
    return
  }
  render([], info('Loading the remote projects…'))
  try {
    const remote = await GH.listRemoteProjects()
    render(remote.filter(r => !localSlugs.has(r.slug)), null)
  } catch (e) {
    render([], info('Remote unavailable: ' + e.message))
  }
}

// Opens a REMOTE-ONLY project: pull, save locally, load.
async function openRemoteProject(slug) {
  closeMenu()
  const existing = await Store.getProject(slug)
  if (existing && !confirm(`A project "${slug}" already exists locally. Overwrite it with the GitHub version?`)) return
  flushEditorToFile()
  if (currentProject && currentProject.id !== slug) await Store.saveProject(currentProject)
  setStatus('Fetching…')
  try {
    const p = await GH.pullProject(slug)
    p.dirty = false   // freshly fetched, hence synchronised
    await Store.saveProject(p)
    await loadProject(p.id)
    setStatus('Project opened ✓', true)
  } catch (e) { setStatus('Error: ' + e.message, true, true) }
}

// The groups, in the order of their first appearance in index.json: that order IS the catalogue's,
// with no second list to keep in step. An entry with no group falls into "Other".
function exampleGroups() {
  const groups = new Map()
  for (const ex of examples) {
    const g = ex.group || 'Other'
    if (!groups.has(g)) groups.set(g, [])
    groups.get(g).push(ex)
  }
  return groups
}

// Fills a panel with the samples of one group. Opening a sample reads it DIRECTLY from the
// repository (the #/playground/sample/<file> route): no copy, and a refresh brings the
// repository's version back. To keep or edit it, the banner offers "Create a project".
function fillExampleGroup(panel, items) {
  for (const ex of items) {
    panel.appendChild(menuItem('📄 ' + ex.name, false, () => {
      closeMenu()
      ctx.navigate('playground', 'sample/' + ex.file)
    }))
  }
}

// The drill-down fallback: the same list, replacing the menu's contents, with a back arrow.
function renderMenuExampleGroup(name, items) {
  projectMenu.innerHTML = ''
  projectMenu.appendChild(menuHeader(name, renderMenuExamples))
  fillExampleGroup(projectMenu, items)
}

async function renderMenuExamples() {
  projectMenu.innerHTML = ''
  projectMenu.appendChild(menuHeader('Open an example', renderMenuRoot))
  examples = await fetch('samples/index.json', { cache: 'no-cache' }).then(r => r.json()).catch(() => examples)
  if (!examples.length) {
    const d = document.createElement('div'); d.className = 'menu-empty'; d.textContent = 'No example.'
    projectMenu.appendChild(d); return
  }
  for (const [name, items] of exampleGroups()) {
    const build = panel => fillExampleGroup(panel, items)
    projectMenu.appendChild(menuFlyItem(
      name + '  (' + items.length + ')', name, build,
      () => renderMenuExampleGroup(name, items)))
  }
}

// GitHub: state and flows.
const TOKEN_URL = 'https://github.com/settings/personal-access-tokens/new'
let ghLogin = null
let statusTimer = null
function setStatus(msg, transient, isError) {
  const el = document.getElementById('status')
  if (!el) return
  el.textContent = msg
  el.style.color = isError ? 'var(--red)' : ''
  clearTimeout(statusTimer)
  if (transient) statusTimer = setTimeout(() => { el.textContent = ''; el.style.color = '' }, 4000)
}

// The complete GitHub setting — the repository AND the token — for the first connection as well as
// for a later change. Both fields show the values IN PLACE, so what is stored can be seen and
// corrected rather than retyped, and an unchanged token is not checked again. Emptying the token
// field keeps the current token; to erase it, disconnect.
function renderMenuConnect() {
  const connected = GH.isConnected()
  const currentToken = GH.getToken() || ''
  projectMenu.innerHTML = ''
  projectMenu.appendChild(menuHeader(connected ? 'GitHub repository and token' : 'Sign in to GitHub', renderMenuGithub))
  const wrap = document.createElement('div'); wrap.className = 'menu-form'
  const info = document.createElement('div'); info.className = 'menu-info'
  info.innerHTML = 'The target repository as <b>owner/repo</b> (it must exist) and a GitHub <b>fine-grained token</b> with the Contents permission: read and write. '
    + `<a href="${TOKEN_URL}" target="_blank" rel="noopener">Create a token ↗</a>`
  const repo = document.createElement('input')
  repo.type = 'text'; repo.className = 'menu-input'; repo.value = GH.getRepo() || ''
  repo.placeholder = 'owner/repo (e.g. myaccount/ollin-projects)'
  repo.title = 'The target repository, as owner/repo - it must exist on GitHub.'
  const input = document.createElement('input')
  input.type = 'password'; input.className = 'menu-input'; input.value = currentToken
  input.placeholder = 'github_pat_… / ghp_…'
  // The token is masked like a password, so without this toggle the prefilled field would show
  // nothing but a row of dots, and nothing could be checked.
  const see = document.createElement('label'); see.className = 'menu-check'
  const box = document.createElement('input'); box.type = 'checkbox'
  box.addEventListener('change', () => { input.type = box.checked ? 'text' : 'password' })
  see.append(box, document.createTextNode('Show the token'))
  const label_txt = connected ? 'Save' : 'Connect'
  const btn = document.createElement('button'); btn.className = 'menu-btn'; btn.textContent = label_txt
  const err = document.createElement('div'); err.className = 'menu-err'
  const connect = async () => {
    const t = input.value.trim()
    if (!t && !connected) return
    const r = repo.value.trim()
    if (!r.includes('/')) { err.textContent = 'Invalid format - use owner/repo'; return }
    try { GH.setRepo(r) } catch (e) { err.textContent = e.message; return }
    // Unchanged: it was validated when it was stored, so there is no need to call GitHub again.
    if (!t || t === currentToken) { renderMenuGithub(); return }
    btn.disabled = true; btn.textContent = 'Checking…'; err.textContent = ''
    // Tested before being stored, so a rejected token does not replace the one that worked, and
    // no other path can set off with an unvalidated token.
    try { const u = await GH.verifyToken(t); GH.setToken(t); ghLogin = u.login; renderMenuGithub() }
    catch (e) { err.textContent = 'Invalid token: ' + e.message; btn.disabled = false; btn.textContent = label_txt }
  }
  btn.addEventListener('click', connect)
  input.addEventListener('keydown', e => { if (e.key === 'Enter') connect() })
  repo.addEventListener('keydown', e => { if (e.key === 'Enter') connect() })
  wrap.append(info, repo, input, see, btn, err)
  projectMenu.appendChild(wrap)
  // When already connected one usually comes to change repository; otherwise, to paste the token.
  if (connected) repo.focus()
  else input.focus()
}

// When GitHub is connected, with a repository set, every NEW project is created on the repository
// at once. Best-effort: on failure (network, permissions, a slug conflict) the project stays local
// and a message says so — "Push to GitHub" remains available for another try.
async function autoPushNewProject(p) {
  if (!GH.isConnected() || !GH.getRepo()) return
  setStatus('Creating on GitHub…')
  try {
    await GH.ensureRepo()
    await GH.pushProject(p, null, {})
    p.dirty = false   // freshly pushed, hence synchronised
    await Store.saveProject(p)   // persiste project.remote (slug, folderSha) + dirty
    setStatus('Project created on GitHub ✓', true)
  } catch (e) {
    setStatus('Created locally — GitHub: ' + (e && e.message ? e.message : e), true, true)
  }
}

// Synchronisation through the `dirty` flag. One model: a project changed locally carries
// `dirty=true`, meaning "to be pushed", and a successful push sets it back to `false`. No content
// hash, no SHA-based conflict detection — the local side is authoritative on a push, the use being
// single-person. The badge has two states: blue means "to push" (dirty), green means synchronised.

function setSyncDot(state) {
  projectBtn.classList.toggle('sync-local',   state === 'local')
  projectBtn.classList.toggle('sync-syncing', state === 'syncing')
  projectBtn.classList.toggle('sync-ok',      state === 'ok')
}

// Eligible for an auto-push: a real project, GitHub connected with a repository configured, and
// `dirty`. It need not already be linked — the first push creates the remote folder.
function canAutoPush(p) {
  return !!(p && !isExample() && GH.isConnected() && GH.getRepo() && p.dirty)
}

// The real push (both the auto-sync and the first send). The badge reads "syncing" while sending,
// and on success `dirty` becomes false and the badge turns green. The error is propagated, so the
// coordinator reschedules: the project stays `dirty` and will be pushed later.
async function sharedRemotePush(project) {
  if (project === currentProject) setSyncDot('syncing')
  await GH.ensureRepo()
  await GH.pushProject(project, null, {})   // sets project.remote (slug, folderSha)
  project.dirty = false
  await Store.saveProject(project)
  if (project === currentProject) {
    updateSyncBadge()
    renderGhRail()   // on the first push the GitHub rail, with the repository's name, becomes visible
  }
}

// The coordinator's onError (for the automatic path only): offline, or an invalid token. The
// project stays `dirty`, the push being unconfirmed, and is pushed later. Kept discreet.
function onRemoteSyncError(err, project) {
  if (project === currentProject) updateSyncBadge()
}

// The badge from the current state: blue when dirty, green otherwise. There is no badge outside
// GitHub (disconnected, no repository configured, or a sample).
function updateSyncBadge() {
  const p = currentProject
  if (!p || isExample() || !GH.isConnected() || !GH.getRepo()) {
    setSyncDot(null)
    return
  }
  setSyncDot(p.dirty ? 'local' : 'ok')
}

const OPEN_CONFLICT_MSG =
  'This project has local changes that have not been pushed, but the version on GitHub has changed too.\n\n'
  + 'OK = fetch GitHub (your local changes will be lost)\n'
  + 'Cancel = keep your local version (it will overwrite GitHub on the next push)'

// Reconciliation on opening a project (non-blocking; offline it keeps the local version). It
// compares the remote folder's SHA with the last known one:
//  • the remote is unchanged, or does not exist: nothing to do, and if `dirty`, schedule the push;
//  • the remote changed and the local side is CLEAN: adopt the remote (an auto-pull);
//  • the remote changed and the local side is `dirty`: ask the user (the guard) whether to fetch
//    the remote or keep the local version, which will overwrite it on the next push.
async function syncOnOpen(project) {
  updateSyncBadge()
  if (isExample() || !GH.isConnected() || !GH.getRepo()) return
  const slug = (project.remote && project.remote.slug) || project.id
  let cur
  try {
    cur = await GH.remoteFolderSha(slug)
  } catch (_) {
    return   // offline or an invalid token: keep the local version
  }
  if (!currentProject || currentProject.id !== project.id) return   // the project changed meanwhile
  const known = (project.remote && project.remote.folderSha) || null
  const remoteChanged = GH.folderMoved(cur, known)
  if (remoteChanged && (!project.dirty || confirm(OPEN_CONFLICT_MSG))) {
    await adoptRemote(project, slug)
    return
  }
  if (project.dirty) sync.schedule(project)   // the local version is kept, so push it
}

// Replaces the current project with the remote version (a pull) and sets `dirty` to false.
async function adoptRemote(project, slug) {
  setStatus('Fetching from GitHub…')
  try {
    const p = await GH.pullProject(slug)
    p.id = project.id
    p.dirty = false
    await Store.saveProject(p)
    await loadProject(p.id)   // reloads the editor and rereads remote.folderSha
  setStatus('Project up to date ✓', true)
  } catch (e) { setStatus('Error: ' + e.message, true, true) }
}

projectBtn.addEventListener('click', e => {
  e.stopPropagation()
  if (projectMenu.style.display === 'block') closeMenu(); else openMenu()
})
// Clicks INSIDE the menu do not bubble up to the document: otherwise, when an item rebuilds the
// menu (innerHTML=''), its target is detached and the "click outside" test below would close the
// menu by mistake, breaking the drill-down.
projectMenu.addEventListener('click', e => e.stopPropagation())
flyMenu.addEventListener('click', e => e.stopPropagation())
const onDocClick = e => {
  if (menuIsOpen() && !projectMenu.contains(e.target) && !flyMenu.contains(e.target) && e.target !== projectBtn)
    closeMenu()
}
document.addEventListener('click', onDocClick)
disposers.push(() => document.removeEventListener('click', onDocClick))
newFileBtn.addEventListener('click', newFile)

// Toggling the side bar. Its state is NOT remembered: it starts closed every time.
const railToggle = document.getElementById('rail-toggle')
const fileRailEl = document.getElementById('file-rail')
let railHidden = true
const railKey = id => 'ollin-rail-open:' + id
function applyRail() {
  fileRailEl.classList.toggle('rail-hidden', railHidden)
  railToggle.classList.toggle('active', !railHidden)
  railToggle.setAttribute('aria-pressed', String(!railHidden))
}
const onRailToggle = () => {
  railHidden = !railHidden
  applyRail()
  if (currentProject) {
    if (!railHidden) localStorage.setItem(railKey(currentProject.id), '1')
    else localStorage.removeItem(railKey(currentProject.id))
  }
}
railToggle.addEventListener('click', onRailToggle)
disposers.push(() => railToggle.removeEventListener('click', onRailToggle))
applyRail()

// Sample mode: direct reading from the repository, with no copy. A banner above the editor says
// that nothing is being saved, with a button to fork it into an editable project.
function removeExampleBanner() {
  const b = document.getElementById('example-banner')
  if (b) b.remove()
}
function showExampleBanner(file) {
  removeExampleBanner()
  const bar = document.createElement('div')
  bar.id = 'example-banner'
  bar.style.cssText = 'display:flex;align-items:center;gap:10px;padding:6px 12px;background:#1e2133;border-bottom:1px solid #3a3f63;font-size:12px;color:#a9b2cf'
  const txt = document.createElement('span')
  txt.innerHTML = '📄 Example <b style="color:#dde4ef">' + file + '</b> — not saved (a refresh reloads the example)'
  const btn = document.createElement('button')
  btn.textContent = 'Create a project'
  btn.style.cssText = 'margin-left:auto;background:var(--accent);color:#fff;border:none;border-radius:5px;padding:4px 10px;font-size:12px;cursor:pointer'
  btn.addEventListener('click', () => forkExampleToProject(file))
  bar.appendChild(txt)
  bar.appendChild(btn)
  const pane = document.getElementById('editor-pane')
  pane.insertBefore(bar, pane.firstChild)
}

async function loadExample(file) {
  currentProject = null
  currentFile = null
  // ctx.v changes on every page load, so a refresh fetches the fresh version.
  // collectSampleProject rejects on a 404 for the entry file.
  let bundle
  try {
    bundle = await Run.collectSampleProject(file, ctx.v)
  } catch (e) {
    removeExampleBanner()
    setStructuralUI(true)
    setEditorText('## ' + (e && e.message ? e.message : 'example not found: ' + file))
    setStatus('Example not found: ' + file, true, true)
    return
  }
  // A TRANSIENT project: the entry file, the imports and the assets, all visible and navigable
  // but not persisted (the TRANSIENT_ID sentinel). A refresh reloads the repository's version.
  currentProject = {
    id: Store.TRANSIENT_ID, name: file, entry: bundle.entry,
    files: bundle.files, resources: bundle.resources,
  }
  currentFile = bundle.entry
  setEditorText(currentProject.files[bundle.entry] ?? '')
  setStructuralUI(false)         // no creating, renaming or deleting on a sample
  renderGhRail(); renderFiles()
  renderResources()
  showExampleBanner(file)
  projectLabel.textContent = file
  // The rail stays CLOSED by default, as for a project; the side button opens it.
}

// The set of project names ALREADY TAKEN, in lower case, locally plus on GitHub when connected.
// `exclude` is an { id, slug } to ignore (the project itself, during a rename). It is fetched once,
// so the input loop does not download again on every attempt.
async function takenProjectNames(exclude = {}) {
  const names = new Set()
  let remoteFailed = false
  for (const p of await Store.listProjects()) {
    if (p.id === exclude.id) continue
    names.add((p.name || '').trim().toLowerCase())
  }
  if (GH.isConnected() && GH.getRepo()) {
    try {
      for (const r of await GH.listRemoteProjects()) {
        if (r.slug === exclude.slug) continue
        names.add((r.name || '').trim().toLowerCase())
      }
    } catch (_) { remoteFailed = true }   // the remote is unreachable, which is reported to the caller
  }
  names.delete('')
  return { names, remoteFailed }
}

// Asks for a FREE project name, taken neither locally nor on the remote repository, looping for
// as long as the name is empty or already taken. It returns the validated name, or null if
// cancelled. `opts` is { label, exclude:{id,slug} }, the exclusion being the project itself during
// a rename.
async function askFreeProjectName(defName, opts = {}) {
  const label = opts.label || 'Project name:'
  if (GH.isConnected() && GH.getRepo()) setStatus('Checking the names…')
  const { names, remoteFailed } = await takenProjectNames(opts.exclude)
  if (remoteFailed) setStatus('Remote names not checked (the repository is unreachable)', true, true)
  else if (GH.isConnected() && GH.getRepo()) setStatus('')
  let name = prompt(label, defName)
  while (name !== null) {
    const clean = name.trim()
    if (!clean) {
      name = prompt('The name cannot be empty. ' + label, defName)
    } else if (names.has(clean.toLowerCase())) {
      name = prompt(`A project "${clean}" already exists (locally or on GitHub). Choose another name:`, clean)
    } else {
      return clean
    }
  }
  return null
}

// An explicit fork: it turns the displayed sample into a persistent, editable project, copying ALL
// of its files (the entry file and the imports) and its resources, not only the open file.
async function forkExampleToProject(file) {
  flushEditorToFile()   // capture the current file's unsaved keystrokes
  const name = await askFreeProjectName(file.replace(/\.ol$/, ''))
  if (!name) return
  const p = await Store.createProject(name)
  if (isExample()) {
    p.files     = { ...currentProject.files }
    p.resources = { ...currentProject.resources }
    p.entry     = currentProject.entry
    delete p.files[Store.MANIFEST]   // regenerated by saveProject
  } else {
    p.files[p.entry] = view.state.doc.toString()
  }
  await Store.saveProject(p)
  await autoPushNewProject(p)   // with a repository set, it is created on GitHub
  Store.setActiveId(p.id)
  ctx.navigate('playground')   // leaves example mode, remounting in project mode
}

// Init.
async function initProjects() {
  await Store.init()
  examples = await fetch('samples/index.json', { cache: 'no-cache' }).then(r => r.json()).catch(() => [])
  projectBtn.disabled = false
  if (exampleFile) {
    await loadExample(exampleFile)
    return
  }
  const active = Store.getActiveId()
  const list = await Store.listProjects()
  const id = (active && list.some(p => p.id === active)) ? active : (list[0] && list[0].id)
  if (id) await loadProject(id)
}
initProjects()

// Output.
const outputEl   = document.getElementById('output')
const canvasEl   = document.getElementById('canvas')
const outputPane = document.getElementById('output-pane')
const dividerEl  = document.getElementById('divider')
const outputHdr  = document.getElementById('output-header')

// The canvas is SHARED, kept in the shell outside a run. We reparent it into this view's render
// area, and app.js puts it back on unmount.
canvasEl.style.display = 'none'
outputPane.appendChild(canvasEl)

// The render area (output plus canvas) only appears while running or paused; at rest the editor
// takes up ALL the space.
function setOutputVisible(visible) {
  outputPane.style.display = visible ? '' : 'none'
  if (dividerEl) dividerEl.style.display = visible ? '' : 'none'
  if (visible) {
    restoreSplit()                       // restore the chosen split
  } else {
    // A full-screen editor: remove the fixed flex bases the drag had set.
    editorPane.style.flex = ''
    outputPane.style.flex = ''
  }
}

const runBtn   = document.getElementById('run-btn')
const stopBtn  = document.getElementById('stop-btn')
let   isPaused  = false   // isRunning is declared above, read by onEditorFocus at init time

const ICON_RUN   = '<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><path d="M3 2l11 6-11 6V2z"/></svg>'
const ICON_STOP  = '<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><rect x="2" y="2" width="12" height="12" rx="2"/></svg>'
const ICON_PAUSE = '<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><rect x="2" y="2" width="4" height="12" rx="1"/><rect x="10" y="2" width="4" height="12" rx="1"/></svg>'
const ICON_RESUME= '<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><path d="M3 2l11 6-11 6V2z"/></svg>'

function setRunning(running) {
  isRunning = running
  if (running) {
    runBtn.classList.add('running')
    runBtn.innerHTML = ICON_STOP + '<span class="btn-label"> Stop</span>'
    stopBtn.style.display = 'flex'
    stopBtn.disabled = false
    document.getElementById('kbar')?.classList.remove('show')   // no typing aid while the program runs
  } else {
    runBtn.classList.remove('running')
    runBtn.innerHTML = ICON_RUN + '<span class="btn-label"> Run</span><kbd>Alt+↵</kbd>'
    stopBtn.style.display = 'none'
    stopBtn.disabled = true
    isPaused = false
    stopBtn.innerHTML = ICON_PAUSE + '<span class="btn-label"> Pause</span>'
  }
}

function clearAndStop() {
  try { ollin && ollin.pauseMainLoop() } catch(_) {}
  canvasEl.style.display = 'none'
  outputEl.style.display = 'block'
  if (outputHdr) outputHdr.style.display = 'flex'
  outputEl.textContent   = ''
  outputEl.className     = ''
  lastErrorLoc = null   // the output is empty, so there is no stale F4 target
  outputPane.style.overflow = ''
  setRunning(false)
  setOutputVisible(false)   // back to the full-screen editor
}

// The location of the last error shown (null when the output is not an error), which is the target
// of the F4 "go to the first error" shortcut.
let lastErrorLoc = null

function showOutput(text) {
  canvasEl.style.display = 'none'
  outputEl.style.display = 'block'
  if (outputHdr) outputHdr.style.display = 'flex'
  outputPane.style.overflow = ''
  if (!text) {
    outputEl.textContent = '(no output)'
    outputEl.className   = ''
    lastErrorLoc = null
  } else if (text.startsWith('error:')) {
    outputEl.className = 'err'
    renderErrorWithLink(text)
  } else {
    outputEl.textContent = text
    outputEl.className   = 'ok'
    lastErrorLoc = null
  }
}

// Extracts the location from an error message.
// The new format (SourceLoc) is "file.ol:42: …".
// The old one, kept for compatibility, is "[file.ol: ]line N: …".
// It returns { file?, line, str, index }, or null when no location is found.
function errLoc(text) {
  // The new format, file.ol:42; the .ol is required, to avoid false positives.
  let m = /(([\w./-]+\.ol):(\d+))/.exec(text || '')
  if (m) return { file: m[2], line: parseInt(m[3], 10), str: m[1], index: m.index }
  // The old format, [file.ol: ]line N.
  m = /(?:([\w./-]+\.ol)\s*:\s*)?line\s+(\d+)/.exec(text || '')
  if (!m) return null
  return { file: m[1] || null, line: parseInt(m[2], 10), str: m[0], index: m.index }
}

// Shows the error in the output area, the "file:line" part becoming a clickable LINK that goes to
// the offending line. There is no automatic jump.
function renderErrorWithLink(text) {
  const loc = errLoc(text)
  lastErrorLoc = loc
  if (!loc) { outputEl.textContent = text; return }
  outputEl.textContent = ''
  outputEl.appendChild(document.createTextNode(text.slice(0, loc.index)))
  const link = document.createElement('span')
  link.className = 'err-link'
  link.textContent = loc.str
  link.title = 'Go to the offending line (F4)'
  link.addEventListener('click', () => gotoError(loc))
  outputEl.appendChild(link)
  outputEl.appendChild(document.createTextNode(text.slice(loc.index + loc.str.length)))
}

// Opens the offending file if need be and puts the cursor on the line, selected so it stays
// highlighted until the next keystroke. Called when the link is CLICKED.
function gotoError(loc) {
  if (!loc) return
  let file = loc.file
  // Resolves the named file (the import's path) to a project key: an exact match, otherwise by
  // base name, the project's keys possibly differing from the resolved path.
  if (file && currentProject) {
    if (currentProject.files[file] === undefined) {
      const base = file.split('/').pop()
      file = scripts(currentProject).find(f => f === file || f.split('/').pop() === base) || null
    }
  } else {
    file = null
  }
  if (file && file !== currentFile) openFile(file)
  const doc = view.state.doc
  const n = Math.max(1, Math.min(loc.line, doc.lines))
  const ln = doc.line(n)
  view.dispatch({ selection: { anchor: ln.from, head: ln.to }, scrollIntoView: true })
  view.focus()
}

// Run.
let ollin = null

// Waits for the visual viewport to return to its full height, the keyboard having closed, with a
// timeout as a fallback should no resize event arrive. It serves to measure the render area AFTER
// the keyboard closes; otherwise the dimensions would be the reduced ones.
function waitViewportRestored(timeout = 500) {
  const vv = window.visualViewport
  if (!vv || window.innerHeight - vv.height < 100)
    return Promise.resolve()   // no visible keyboard (any more)
  return new Promise(resolve => {
    let done = false
    const finish = () => {
      if (done) return
      done = true
      vv.removeEventListener('resize', onResize)
      clearTimeout(timer)
      resolve()
    }
    const onResize = () => { if (window.innerHeight - vv.height < 100) finish() }
    vv.addEventListener('resize', onResize)
    const timer = setTimeout(finish, timeout)
  })
}

// Starts the execution, from cold. It does not toggle: see run(), relaunch() and stopExec().
async function launch() {
  if (!ollin) return
  clearTimeout(autoexecTimer)   // every start (button, Alt+Enter, auto) counts as a restart, so cancel the pending one
  // Starting with the keyboard OPEN, on a touch device: close it first and wait for the viewport
  // to come back. Otherwise the render area would be measured REDUCED, by the keyboard, giving too
  // small a canvas and a wrong size once the keyboard closed.
  if (isPhone && document.activeElement === view.contentDOM) {
    view.contentDOM.blur()
    await waitViewportRestored()
  }
  try { ollin.pauseMainLoop() } catch(_) {}
  setRunning(false)
  outputEl.className = ''
  lastErrorLoc = null   // a new run: F4 must no longer aim at the previous error
  // Show the area BEFORE execute, then MEASURE in JS and hand the result to the engine: reading
  // the DOM from C++ at init time is subject to a layout race — a flex box just out of
  // display:none sometimes reads clientWidth=0, hence W/H=0 and an empty canvas. JS, on the other
  // hand, has a reliable layout after the reflow (getBoundingClientRect). The `window` module
  // reads __ollinRenderW/H first (see window_module.cpp).
  setOutputVisible(true)
  const _rr = outputPane.getBoundingClientRect()
  window.__ollinRenderW = Math.round(_rr.width)
  window.__ollinRenderH = Math.round(_rr.height)
  flushEditorToFile()
  // Preloading, execution and error handling: logic SHARED with the standalone mode (run.html)
  // through pg-run.js, so there is no duplication and no drift.
  Run.loadProjectIntoRuntime(ollin, currentProject)
  const code = currentProject ? (currentProject.files[currentProject.entry] ?? '')
                              : view.state.doc.toString()
  // In sample or draft mode the 3D models referenced (graphics.model("x.obj")) are preloaded from
  // samples/; user projects go through their own resources.
  if (!currentProject) {
    const imported = await Run.preloadSampleImports(ollin, code, ctx.v)
    await Run.preloadSampleModels(ollin, code + '\n' + imported, ctx.v)   // the imports' models too
  }
  // The `data` module's project scope: the project's id, or 'sample:<file>' for a sample.
  window.__ollinDataProject = isExample() ? ('sample:' + exampleFile) : (currentProject ? currentProject.id : '_')
  Run.runProgram(ollin, code, canvasEl, {
    filename:  currentProject ? (currentProject.entry || '') : (exampleFile || ''),
    onError:   (msg) => { setRunning(false); showOutput(msg) },
    onRunning: () => {
      outputPane.style.overflow = 'hidden'
      if (outputHdr) outputHdr.style.display = 'none'
      setRunning(true)   // the __ollinGfxKbdArmed flag is set by runProgram (pg-run.js)
    },
    onOutput:  (out) => showOutput(out),
  })
}

// The Run button toggles: it reads "Stop" while the program runs.
function run() {
  if (!ollin) return
  if (isRunning) { clearAndStop(); return }
  launch()
}

// Alt+Enter runs, or RESTARTS from cold when a program is already running.
function relaunch() {
  if (!ollin) return
  if (isRunning) clearAndStop()
  launch()
}

// Escape stops the running program, and does nothing otherwise.
function stopExec() {
  if (isRunning) clearAndStop()
}

runBtn.addEventListener('click', run)

// Auto mode (a deferred restart), available on every target. There is no pointer restriction: a
// touch device with a keyboard, an iPad say, edits as much as a desktop. The button is visible as
// soon as the element exists.
const autoexecWrap = document.getElementById('autoexec-wrap')
const autoexecChk  = document.getElementById('autoexec-chk')
if (autoexecWrap) {
  autoexecWrap.style.display = ''
  const onAutoexec = () => {
    autoexecWrap.classList.toggle('on', autoexecChk.checked)
    if (!autoexecChk.checked) {
      clearTimeout(autoexecTimer)   // unchecked: cancel any pending restart
      return
    }
    if (!isRunning) relaunch()      // checked: start at once unless the script is already running
  }
  autoexecChk.addEventListener('change', onAutoexec)
  disposers.push(() => autoexecChk.removeEventListener('change', onAutoexec))
}
stopBtn.addEventListener('click', () => {
  if (isPaused) {
    try { ollin.resumeMainLoop() } catch(_) {}
    isPaused = false
    stopBtn.innerHTML = ICON_PAUSE + '<span class="btn-label"> Pause</span>'
  } else {
    try { ollin.pauseMainLoop() } catch(_) {}
    isPaused = true
    stopBtn.innerHTML = ICON_RESUME + '<span class="btn-label"> Reprendre</span>'
  }
})

// Format: reindents the code (pg-format.js) on demand. It changes ONLY the indentation and
// preserves the cursor, at the same line and column in the content. It abstains when the blocks
// are unbalanced, giving an error message and changing nothing.
function doFormat() {
  const r = Fmt.formatOllin(view.state.doc.toString())
  if (!r.ok) { setStatus('Cannot format: ' + r.error, true, true); return }
  if (r.code === view.state.doc.toString()) { setStatus('Already formatted ✓', true); return }
  const head = view.state.selection.main.head
  const oldLine = view.state.doc.lineAt(head)
  const contentCol = Math.max(0, head - oldLine.from - (oldLine.text.length - oldLine.text.trimStart().length))
  const ln = oldLine.number
  view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: r.code } })
  const nl = view.state.doc.line(Math.min(ln, view.state.doc.lines))   // the same line number, the count being preserved
  const newIndent = nl.text.length - nl.text.trimStart().length
  view.dispatch({ selection: { anchor: Math.min(nl.from + newIndent + contentCol, nl.to) }, scrollIntoView: true })
  view.focus()
  setStatus('Code formatted ✓', true)
}
document.getElementById('format-btn').addEventListener('click', doFormat)

// Copy.
const copyBtn = document.getElementById('copy-btn')
const ICON_COPY = ICONS.copy   // shared (cm-shared.js)
const ICON_OK   = ICONS.ok
copyBtn.addEventListener('click', () => {
  navigator.clipboard.writeText(view.state.doc.toString()).then(() => {
    copyBtn.innerHTML = ICON_OK + '<span class="btn-label"> Copied!</span>'
    copyBtn.style.color        = 'var(--green)'
    copyBtn.style.borderColor  = 'var(--green)'
    setTimeout(() => {
      copyBtn.innerHTML = ICON_COPY + '<span class="btn-label"> Copier</span>'
      copyBtn.style.color = ''
      copyBtn.style.borderColor = ''
    }, 1500)
  })
})

// Full-screen mode (the #/run view, in the SAME window). It switches to #/run IN the current
// window rather than a new tab: a new tab creates a separate GLFW context whose keyboard listener
// breaks Backspace and Tab on returning to the editor. The active project is committed to
// IndexedDB before the switch, and the #/run view reloads it from there.
const standaloneBtn = document.getElementById('standalone-btn')
standaloneBtn.addEventListener('click', async () => {
  if (exampleFile) {
    // Sample mode: run the SAME sample, fresh, standalone, with no project.
    ctx.navigate('run', 'sample/' + exampleFile)
    return
  }
  try {
    flushEditorToFile()
    if (currentProject) {
      Store.setActiveId(currentProject.id)
      await Store.saveProject(currentProject)
    }
  } catch (_) {}
  ctx.navigate('run')
})

// The help popup (the shortcuts), rendered once from SHORTCUTS and opened by the "Help" button or
// by F1.
const helpOverlay = document.getElementById('help-overlay')
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
// On macOS, CodeMirror maps Ctrl to ⌘ (the Mod- spec), so we show the Mac symbols (⌘ ⌥ ⇧) for the
// help to match the real keys. Elsewhere it is Ctrl, Alt and Shift.
const IS_MAC = /Mac|iPhone|iPad|iPod/.test(navigator.platform || navigator.userAgent || '')
const osKey = k => IS_MAC ? k.replace(/Ctrl\+?/g, '⌘').replace(/Alt\+?/g, '⌥').replace(/Shift\+?/g, '⇧') : k
function renderHelp() {
  const body = document.getElementById('help-body')
  if (!body) return
  body.innerHTML = SHORTCUTS.map(group => {
    const rows = group.items.map(it => {
      const keys = it.keys.map(k => '<kbd>' + esc(osKey(k)) + '</kbd>')
        .join(it.sep ? '<span class="plus">' + esc(it.sep) + '</span>' : '<span class="plus">+</span>')
      return '<div class="help-row"><span class="help-desc">' + esc(osKey(it.desc)) + '</span><span class="help-keys">' + keys + '</span></div>'
    }).join('')
    return '<div class="help-cat">' + esc(group.cat) + '</div>' + rows
  }).join('')
}
function helpOpen() {
  return helpOverlay && !helpOverlay.hasAttribute('hidden')
}
function openHelp() {
  if (!helpOverlay) return
  renderHelp()
  helpOverlay.removeAttribute('hidden')
}
function closeHelp() {
  if (helpOverlay) helpOverlay.setAttribute('hidden', '')
}
function toggleHelp() {
  helpOpen() ? closeHelp() : openHelp()
}
document.getElementById('help-close')?.addEventListener('click', closeHelp)
helpOverlay?.addEventListener('click', e => { if (e.target === helpOverlay) closeHelp() })

// Reload and empty the cache: it clears the Cache API then reloads (the editor's code is kept in
// localStorage). Useful for picking up a freshly deployed WASM.
const reloadBtn = document.getElementById('reload-btn')
reloadBtn.addEventListener('click', hardReload)   // the shared hard reload (pg-run.js, through ctx)

// Image upload. Images are handled ONLY through the rail's "Resources" section, as the files are:
// the "＋" opens this hidden picker. There is no dedicated button in the toolbar, which keeps it
// consistent with the files, resources being used less often.
const imgFileInput = document.getElementById('img-file-input')

// The images loaded become RESOURCES of the active project, and are persisted.
imgFileInput.addEventListener('change', () => {
  const files = Array.from(imgFileInput.files)
  if (!files.length || !currentProject || isExample()) return
  files.forEach(file => {
    const ext  = file.name.split('.').pop().toLowerCase()
    const name = file.name
    const reader = new FileReader()
    reader.onload = async e => {
      const b64 = (e.target.result.split(',')[1]) ?? ''   // "data:...;base64,xxxx"
      currentProject.resources[name] = { b64, ext }
      await persist(currentProject)
      if (ollin) {
        // 3D models go to preloadModel, images to preloadImage.
        if ((ext === 'obj' || ext === 'gltf' || ext === 'glb') && ollin.preloadModel) {
          ollin.preloadModel(name, b64, ext)
        } else if (ollin.preloadImage) {
          ollin.preloadImage(name, b64, ext)
        }
      }
      renderResources()
    }
    reader.readAsDataURL(file)
  })
  imgFileInput.value = ''
})

// The "＋" of the Resources section opens the same file picker.
newResBtn.addEventListener('click', () => imgFileInput.click())

// WASM.
const statusEl = document.getElementById('status')

// The SHARED WASM runtime, loaded once by app.js and reused by every view. It is already bound to
// the shell's shared <canvas>.
getOllin().then(m => {
  ollin              = m
  runBtn.disabled    = false
  statusEl.textContent = 'Ready ✓'
  setTimeout(() => { statusEl.textContent = '' }, 2000)
}).catch(err => {
  statusEl.textContent = 'WASM error: ' + (err?.message ?? err)
})

// Divider resize.
const divider    = document.getElementById('divider')
const editorPane = document.getElementById('editor-pane')
let   dragging   = false

const SPLIT_KEY = 'ollin-pg-split'

function applySplit(pct) {
  editorPane.style.flex = `0 0 ${pct}%`
  outputPane.style.flex = `0 0 ${100 - pct}%`
}

// Restores the saved split, when the render area comes back. At rest, with the area hidden, NO
// flex is set, so the editor fills everything.
function restoreSplit() {
  const pct = parseFloat(localStorage.getItem(SPLIT_KEY))
  if (pct >= 15 && pct <= 85) {
    applySplit(pct)
  } else {
    editorPane.style.flex = ''
    outputPane.style.flex = ''
  }
}

function startDrag(e) {
  dragging = true
  divider.classList.add('dragging')
  e.preventDefault()
}
function moveDrag(clientX, clientY) {
  if (!dragging) return
  const layout = document.getElementById('layout')
  const rect   = layout.getBoundingClientRect()
  const mobile = window.innerWidth <= 640
  const pct = mobile
    ? Math.min(85, Math.max(15, (clientY - rect.top)  / rect.height * 100))
    : Math.min(85, Math.max(15, (clientX - rect.left) / rect.width  * 100))
  applySplit(pct)
}
function endDrag() {
  if (!dragging) return
  dragging = false
  divider.classList.remove('dragging')
  const pct = parseFloat(editorPane.style.flex.split(' ')[2])
  if (!isNaN(pct)) localStorage.setItem(SPLIT_KEY, pct)
}

const onDocMouseMove = e => moveDrag(e.clientX, e.clientY)
const onDocMouseUp    = () => endDrag()
const onDocTouchMove  = e => { if (dragging) { moveDrag(e.touches[0].clientX, e.touches[0].clientY); e.preventDefault() } }
const onDocTouchEnd   = () => endDrag()
divider.addEventListener('mousedown',  e => startDrag(e))
document.addEventListener('mousemove', onDocMouseMove)
document.addEventListener('mouseup',   onDocMouseUp)
divider.addEventListener('touchstart', e => startDrag(e), { passive: false })
document.addEventListener('touchmove',  onDocTouchMove, { passive: false })
document.addEventListener('touchend',   onDocTouchEnd)
disposers.push(() => {
  document.removeEventListener('mousemove', onDocMouseMove)
  document.removeEventListener('mouseup',   onDocMouseUp)
  document.removeEventListener('touchmove',  onDocTouchMove)
  document.removeEventListener('touchend',   onDocTouchEnd)
})

// Leaving the view during a graphics run: pause the raylib loop, which would otherwise keep
// running on a detached canvas, disarm the keyboard interception, DESTROY the CM6 editor (which
// removes its global observers and listeners, so nothing leaks on every revisit) and release the
// debug reference.
disposers.push(() => {
  try { ollin && ollin.pauseMainLoop() } catch (_) {}
  // __ollinGfxKbdArmed is NOT set back to false: the GLFW listener stays on window after the
  // unmount, so the counter-measure must remain armed page-wide.
  clearTimeout(autoexecTimer)   // no ghost restart after the view is unmounted
  try { view.destroy() } catch (_) {}
  if (window.__ollinView === view) window.__ollinView = undefined
})

return () => { for (const d of disposers) d() }
}
