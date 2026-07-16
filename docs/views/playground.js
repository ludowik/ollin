// Vue PLAYGROUND — init(ctx) appelée par app.js après montage du fragment.
//   ctx = { root, getOllin, hardReload, navigate }
// getOllin() : runtime WASM PARTAGÉ (une instance SPA). Le corps garde son
// indentation d'origine (déplacé tel quel depuis playground.html pour éviter
// toute corruption des chaînes multi-lignes lors d'une réindentation).
import {
  EditorState,
  EditorView, lineNumbers, keymap, drawSelection, highlightActiveLine, highlightActiveLineGutter,
  defaultKeymap, historyKeymap, history, indentWithTab,
  syntaxHighlighting, indentUnit, codeFolding, foldGutter, foldKeymap, foldService,
  autocompletion, completionKeymap, acceptCompletion,
  closeBrackets, closeBracketsKeymap,
} from '../vendor/codemirror.js'
import { CODE_DISPLAY, CODE_THEME_BASE, ICONS } from '../cm-shared.js'
import { ollinLang, ollinHighlight } from '../cm-lang.js'

export async function init(ctx) {
const { getOllin, hardReload } = ctx
const disposers = []   // écouteurs globaux à retirer au démontage

const Store = await import('../pg-store.js?v=' + ctx.v)
const GH    = await import('../pg-github.js?v=' + ctx.v)
const Run   = await import('../pg-run.js?v=' + ctx.v)   // exécution partagée avec run.html
const Fmt   = await import('../pg-format.js?v=' + ctx.v)   // formateur « à la demande »
const { pinToVisualViewport } = await import('../pg-viewport.js?v=' + ctx.v)

// Barre d'outils collee au haut du VISIBLE quand le clavier mobile s'ouvre
// (sinon elle derive/disparait sur iOS). Actif tant que la vue est montee.
disposers.push(pinToVisualViewport())

// Mode EXEMPLE : route #/playground/sample/<fichier> → on ouvre l'exemple
// directement depuis le dépôt (samples/…), SANS copie ni persistance. Édition
// libre à l'écran mais non enregistrée ; un refresh recharge la version du dépôt.
// Bouton « Créer un projet » pour forker à la demande. (parse partagé, pg-run.js)
const exampleFile = Run.sampleFromAnchor(ctx.anchor)

// ── Ollin syntax ──────────────────────────────────────────────────────────
// KEYWORDS / BUILTINS / ollinLang / ollinHighlight : importés de cm-lang.js.

const ollinTheme = EditorView.theme({
  '&': { background: '#000000', color: '#c9d1e0', fontSize: '14.5px', height: '100%' },
  '.cm-scroller': { fontFamily: "'JetBrains Mono','Fira Code','Cascadia Code',Consolas,monospace", lineHeight: '1.65' },
  '.cm-content': { padding: '14px 0', caretColor: '#7c83ff' },
  ...CODE_DISPLAY,   // réglages d'affichage partagés (cm-shared.js)
  '.cm-gutters': { background: '#000000', color: '#3d4463', border: 'none', borderRight: '1px solid #2e3150' },
  ...CODE_THEME_BASE,   // ligne active, curseur, sélection (partagés cm-shared.js)
  '&.cm-focused': { outline: 'none' },

  /* autocomplete dropdown */
  '.cm-tooltip.cm-tooltip-autocomplete': { background: '#1e2133', border: '1px solid #3a3f5c', borderRadius: '6px', boxShadow: '0 4px 16px rgba(0,0,0,0.5)', padding: '2px 0' },
  '.cm-tooltip-autocomplete > ul': { fontFamily: "'JetBrains Mono','Fira Code',Consolas,monospace", fontSize: '12.5px', maxHeight: '280px' },
  '.cm-tooltip-autocomplete > ul > li': { padding: '3px 10px 3px 6px', color: '#c9d1e0', lineHeight: '1.5' },
  '.cm-tooltip-autocomplete > ul > li[aria-selected]': { background: '#2d3259', color: '#ffffff' },
  '.cm-completionLabel': { color: '#c9d1e0' },
  '.cm-completionDetail': { color: '#7c85a2', fontStyle: 'italic', marginLeft: '6px' },
  '.cm-completionIcon': { opacity: 0.7, width: '16px', marginRight: '4px' },
  '.cm-completionIcon-keyword': { color: '#569CD6' },
  '.cm-completionIcon-function': { color: '#DCDCAA' },
  '.cm-completionIcon-constant': { color: '#4FC1FF' },
  '.cm-completionIcon-namespace': { color: '#C586C0' },
  '[aria-selected] .cm-completionLabel': { color: '#ffffff' },
  '[aria-selected] .cm-completionDetail': { color: '#a0aabf' },
})

// ── Autocompletion ────────────────────────────────────────────────────────
const kw  = label => ({ label, type: 'keyword' })
const cst = (label, detail) => ({ label, type: 'constant', detail })

// Fonction connue : à l'acceptation, insère l'appel avec ses paramètres de base
// PRÉ-SAISIS (ex. circle → « circle(x, y, rayon) »), la liste des params étant
// sélectionnée pour être remplacée directement. Sans paramètre → « name() »,
// curseur après la parenthèse. Les params sont tirés de la signature (detail).
const fn = (label, detail) => {
  const mo = detail && detail.match(/\(([^]*)\)/)
  let params = mo ? mo[1].trim() : ''
  if (params === '...') params = ''            // varargs → parenthèses vides
  return {
    label, type: 'function', detail,
    apply: (view, c, from, to) => {
      const name = c.label
      const insert = `${name}(${params})`
      const open = from + name.length + 1
      view.dispatch({
        changes: { from, to, insert },
        selection: params ? { anchor: open, head: open + params.length }   // params sélectionnés
                          : { anchor: from + insert.length },              // curseur après ()
      })
    },
  }
}

// « func » : insère seulement « func » + espace (curseur après), prêt à taper
// le nom. Le squelette complet (params + corps + end) est produit à l'acceptation
// du NOM de fonction connu — sans jamais doubler les parenthèses.
const AC_FUNC = {
  label: 'func', type: 'keyword', detail: 'définir une fonction',
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
  fn('typeof', 'typeof(v) → string'),   fn('Color', 'Color(r, g, b [, a])'),
  fn('len',    'len(v) → int'),         fn('mem',    'mem() → int (octets utilisés)'),
]

// Hooks de cycle de vie appelés par le moteur : insérés en squelette COMPLET
// (func … end), le « func » n'étant pas répété s'il est déjà tapé. Le curseur
// se place dans le corps (nouvelle ligne indentée). Évite les fautes de frappe.
function lifecycle(name, params, detail) {
  return {
    label: name, type: 'function', detail,
    apply: (view, c, from, to) => {
      const before = view.state.doc.sliceString(view.state.doc.lineAt(from).from, from)
      const prefix = /\bfunc\s+\S*$/.test(before) ? '' : 'func '   // ne pas doubler « func »
      const head = `${prefix}${name}(${params})\n    `
      view.dispatch({
        changes: { from, to, insert: head + '\nend' },
        selection: { anchor: from + head.length },   // curseur dans le corps indenté
      })
    },
  }
}
const AC_LIFECYCLE = [
  lifecycle('setup',  '',   'moteur — une fois au démarrage'),
  lifecycle('update', 'dt', 'moteur — logique, chaque frame'),
  lifecycle('draw',   '',   'moteur — rendu, chaque frame'),
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
    fn('math.frac','frac(x)'),     fn('math.noise','noise(x[,y[,z]])'), fn('math.noise_seed','noise_seed(n)'),
    fn('math.sin','sin(x)'),       fn('math.cos','cos(x)'),        fn('math.tan','tan(x)'),
    fn('math.asin','asin(x)'),     fn('math.acos','acos(x)'),      fn('math.atan','atan(x)'),
    fn('math.atan2','atan2(y,x)'),
    fn('math.deg','deg(rad)'),      fn('math.rad','rad(deg)'),
    fn('math.is_nan','is_nan(x)'), fn('math.is_inf','is_inf(x)'),
    fn('math.rand','rand([lo,hi])'), fn('math.rand_int','rand_int([lo,]hi)'), fn('math.seed','seed(n)'),
  ],
  graphics: [
    fn('graphics.canvas','canvas(w,h[,title])'),   fn('graphics.run','run(callback)'),
    fn('graphics.clear','clear([color]) — alpha<1 = fondu'),
    fn('graphics.blendMode','blendMode(mode) — "add"/blend.ADD…'),
    fn('graphics.strokeSize','strokeSize(n)'),     fn('graphics.stroke','stroke([color]|r,g,b)'),
    fn('graphics.noStroke','noStroke()'),
    fn('graphics.fill','fill([color])'),           fn('graphics.noFill','noFill()'),
    fn('graphics.tint','tint([color])'),           fn('graphics.noTint','noTint()'),
    fn('graphics.begin_draw','begin_draw()'),      fn('graphics.end_draw','end_draw()'),
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
    fn('graphics.draw_text','draw_text(text,x,y,size[,color])'),
    fn('graphics.fps','fps()→int'),                fn('graphics.is_open','is_open()→bool'),
    fn('graphics.close','close()'),                fn('graphics.quit','quit()'),
    // ── 3D ──
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
    // quaternions
    fn('graphics.quat','quat() → Quat (identité)'),
    fn('graphics.quat_axis','quat_axis(ax,ay,az, deg) → Quat'),
    fn('graphics.quat_euler','quat_euler(pitch,yaw,roll) → Quat'),
    fn('graphics.rotateq','rotateq(q)'),
  ],
  image: [
    fn('image.load','load(path) → img'),
    fn('image.load_data','load_data(format, base64) → img'),
    fn('image.create','create(w, h) → img'),
    fn('image.begin_draw','begin_draw(img)'),
    fn('image.end_draw','end_draw()'),
    fn('image.draw','draw(img, x, y [, w, h [, tint]])'),
    fn('image.unload','unload(img)'),
    fn('image.set_pixel','set_pixel(img, x, y, color)'),
    fn('image.get_pixel','get_pixel(img, x, y) → color'),
    fn('image.begin_pixels','begin_pixels(img)'),
    fn('image.end_pixels','end_pixels(img)'),
  ],
  colors: [
    cst('colors.BLACK',''),   cst('colors.WHITE',''),  cst('colors.RED',''),
    cst('colors.GREEN',''),   cst('colors.BLUE',''),   cst('colors.YELLOW',''),
    cst('colors.GRAY',''),    cst('colors.ORANGE',''), cst('colors.PINK',''),
    cst('colors.PURPLE',''),  cst('colors.BROWN',''),  cst('colors.DARKGRAY',''),
    cst('colors.SKYBLUE',''), cst('colors.LIME',''),   cst('colors.MAGENTA',''),
  ],
  blend: [
    cst('blend.ALPHA','fusion normale (défaut)'), cst('blend.ADD','additif (glow)'),
    cst('blend.MULTIPLY','multiplié'),            cst('blend.ADD_COLORS','somme des couleurs'),
    cst('blend.SUBTRACT','soustractif'),          cst('blend.PREMULTIPLY','alpha prémultiplié'),
  ],
  Color: [
    fn('Color.random','random() → couleur aléatoire'),
  ],
  string: [
    fn('string.len','len(s) → int'),
    fn('string.upper','upper(s)'), fn('string.lower','lower(s)'), fn('string.trim','trim(s[,chars])'),
    fn('string.ltrim','ltrim(s[,chars])'), fn('string.rtrim','rtrim(s[,chars])'),
    fn('string.char','char(s,i)'), fn('string.substr','substr(s,start[,len])'),
  ],
  window: [
    cst('window.width','largeur de la zone de rendu (px)'),
    cst('window.height','hauteur de la zone de rendu (px)'),
  ],
  keyboard: [
    fn('keyboard.keypressed','keypressed(key) — à définir : appelée à l\'appui'),
    fn('keyboard.keyrelease','keyrelease(key) — à définir : appelée au relâchement'),
  ],
  mouse: [
    fn('mouse.pressed','pressed(x,y) — à définir : appelée au clic'),
    fn('mouse.released','released(x,y) — à définir : au relâchement'),
    fn('mouse.moved','moved(x,y) — à définir : au déplacement'),
  ],
}

// Commande « démarrer l'autocomplétion » (binding Ctrl-Space de CodeMirror) —
// réutilisée pour rouvrir la liste après avoir complété un nom de module.
const startCompletion = (completionKeymap.find(b => b.key === 'Ctrl-Space') || {}).run

function ollinComplete(context) {
  const dotWord = context.matchBefore(/[a-zA-Z_]\w*\.\w*/)
  if (dotWord) {
    const dot    = dotWord.text.indexOf('.')
    const prefix = dotWord.text.slice(0, dot)
    const members = MODULE_MEMBERS[prefix]
    if (members) {
      // Filtre + tri ALPHABÉTIQUE nous-mêmes, et `filter: false` pour que CodeMirror
      // conserve NOTRE ordre au lieu de re-classer par « pertinence floue » (qui
      // donnait un ordre déroutant : endChunk, drawChunk, freeChunk, beginChunk…).
      // Sans validFor → CM ré-interroge à chaque frappe et re-filtre. Sous-chaîne,
      // insensible à la casse, pour rester tolérant comme avant.
      const q = dotWord.text.slice(dot + 1).toLowerCase()
      const opts = members
        .map(m => ({ ...m, label: m.label.slice(prefix.length + 1) }))
        .filter(m => m.label.toLowerCase().includes(q))
        .sort((a, b) => a.label.localeCompare(b.label))
      return { from: dotWord.from + dot + 1, options: opts, filter: false }
    }
    return null
  }
  const word = context.matchBefore(/\w+/)
  if (!word || (word.from === word.to && !context.explicit)) return null
  // Compléter un module (math, graphics…) insère « nom. » et rouvre aussitôt la
  // liste sur ses membres — on n'a plus à taper le point à la main.
  const moduleNames = Object.keys(MODULE_MEMBERS).map(m => ({
    label: m, type: 'namespace',
    apply: (view, c, from, to) => {
      view.dispatch({ changes: { from, to, insert: m + '.' }, selection: { anchor: from + m.length + 1 } })
      if (startCompletion) startCompletion(view)
    },
  }))
  return {
    from: word.from,
    options: [AC_FUNC, ...AC_LIFECYCLE, ...AC_KEYWORDS, ...AC_BUILTINS, ...moduleNames],
    validFor: /^\w*$/,
  }
}

// ── Repliement de blocs (fold) ──────────────────────────────────────────────
// Ollin est une StreamLanguage (pas d'arbre Lezer) → on fournit les bornes de
// bloc via le facet standard `foldService`. Un bloc s'ouvre sur func/if/while/
// for/class/try/switch et se ferme sur `end` ; on suit la profondeur.
const FOLD_OPENERS = /\b(?:func|if|while|for|class|try|switch)\b/g
const FOLD_ENDS    = /\bend\b/g
const countMatches = (s, re) => (s.match(re) || []).length

function ollinFoldRange(state, lineStart) {
  const first = state.doc.lineAt(lineStart)
  const head = first.text.replace(/##.*$/, '')          // ignorer les commentaires
  let depth = countMatches(head, FOLD_OPENERS) - countMatches(head, FOLD_ENDS)
  if (depth <= 0)
    return null                                          // pas un ouvrant net (ou refermé sur la ligne)
  for (let n = first.number + 1; n <= state.doc.lines; n++) {
    const line = state.doc.line(n)
    const body = line.text.replace(/##.*$/, '')
    depth += countMatches(body, FOLD_OPENERS) - countMatches(body, FOLD_ENDS)
    if (depth <= 0) {
      const from = first.to                              // fin de la ligne d'ouverture
      const to = state.doc.line(n - 1).to                // fin de la dernière ligne avant `end`
      return to > from ? { from, to } : null
    }
  }
  return null
}

// ── Editor ────────────────────────────────────────────────────────────────
// Le contenu est piloté par le projet actif (voir la section « Projets » plus
// bas) : l'éditeur démarre vide puis reçoit le fichier courant après Store.init.
let saveTimer   = null
let loadingFile = false   // true pendant un chargement programmatique → pas d'autosave

// Keymap de l'éditeur, gardé en référence : réutilisé tel quel par le garde-fou
// clavier « pendant un run » (voir plus bas) pour déléguer aux VRAIES commandes
// CodeMirror au lieu de les réimplémenter.
// closeBracketsKeymap en tête : Backspace supprime une paire vide «()» d'un coup.
const editKeymap = [{ key: 'Tab', run: acceptCompletion }, ...closeBracketsKeymap, ...completionKeymap, indentWithTab, ...defaultKeymap, ...historyKeymap, ...foldKeymap]

// Extensions de l'éditeur, réutilisées pour recréer un état VIERGE à chaque
// chargement de fichier (setEditorText) → historique d'annulation propre par
// fichier (cf. setEditorText).
const editorExtensions = [
      ollinLang, syntaxHighlighting(ollinHighlight), lineNumbers(), ollinTheme,
      EditorView.lineWrapping,
      // iOS Safari : la barre prédictive « QuickType » intercepte le 1er
      // Backspace (→ « sans effet ») et double des caractères. autocorrect/
      // autocapitalize/spellcheck ne suffisent pas toujours à la masquer :
      // autocomplete='off' + inputmode='text' la coupent plus franchement.
      EditorView.contentAttributes.of({
        autocorrect: 'off', autocapitalize: 'off', autocomplete: 'off',
        spellcheck: 'false', inputmode: 'text',
      }),
      codeFolding(), foldGutter(), foldService.of(ollinFoldRange),
      history(), drawSelection(), highlightActiveLine(), highlightActiveLineGutter(),
      keymap.of(editKeymap),
      keymap.of([
        { key: 'Alt-Enter', run: () => { relaunch(); return true } },   // lance / relance
        { key: 'Escape', run: () => { if (isRunning) { stopExec(); return true } return false } },
        { key: 'Shift-Alt-f', run: () => { doFormat(); return true } },   // reformater
        // Chord (Alt+K puis C/U) : commenter / dé-commenter les lignes sélectionnées.
        // Deux variantes : Alt relâché avant la 2e touche, OU Alt maintenu (Alt+K Alt+C).
        { key: 'Alt-k c', run: (v) => toggleLineComment(v, true) },
        { key: 'Alt-k u', run: (v) => toggleLineComment(v, false) },
        { key: 'Alt-k Alt-c', run: (v) => toggleLineComment(v, true) },
        { key: 'Alt-k Alt-u', run: (v) => toggleLineComment(v, false) },
      ]),
      indentUnit.of('    '),
      // Auto-paires natives : «(» insère «()», entoure la sélection si elle
      // existe, et Backspace supprime la paire vide (closeBracketsKeymap).
      closeBrackets(),
      autocompletion({ override: [ollinComplete], activateOnTyping: true }),
      EditorView.updateListener.of(update => {
        if (!update.docChanged || loadingFile) return
        clearTimeout(saveTimer)
        saveTimer = setTimeout(scheduleSave, 500)
      }),
]

const view = new EditorView({
  state: EditorState.create({ doc: '', extensions: editorExtensions }),
  parent: document.getElementById('editor-wrap'),
})

// Commente (add=true) / dé-commente (add=false) les lignes couvertes par la
// sélection. Préfixe de commentaire Ollin = '## ' (cf. grammar.ebnf line_comment).
// Insertion/retrait au 1er caractère non-blanc → l'indentation est préservée ;
// les lignes vides sont ignorées à l'ajout. Raccourcis : Alt+K puis C / U.
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
      if (line.text.trim() === '') continue   // ne pas commenter une ligne vide
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

// ── Backspace/nav quand le runtime graphique est armé ──────────────────────
// Dès qu'un projet graphique tourne (Run), le runtime raylib (couche GLFW
// d'Emscripten) installe un écouteur keydown GLOBAL (window, phase capture) qui
// fait preventDefault UNIQUEMENT sur Backspace et Tab (vérifié dans
// wasm/ollin.js — GLFW.onKeydown) pour empêcher le navigateur de reculer/
// défiler. Cet écouteur reste tant que le contexte graphique vit (un simple
// Arrêt ne le retire pas). Or CodeMirror IGNORE tout keydown déjà
// defaultPrevented → dans l'éditeur, Backspace et Tab « n'ont plus d'effet ».
// Parade : un écouteur enregistré ICI (au chargement, donc AVANT celui de GLFW)
// en phase capture. Tant que le runtime a été armé (`runtimeArmed`) et que
// l'éditeur a le focus, on exécute Backspace/Tab via les VRAIES commandes
// CodeMirror (le même `editKeymap` que l'éditeur → deleteCharBackward, delete
// GroupBackward, indentMore/Less, acceptCompletion…), puis on stoppe
// l'événement pour que GLFW ne le voie pas. On ne touche QU'À ces deux touches :
// toutes les autres passent normalement à CodeMirror (GLFW ne les bloque pas),
// donc aucune régression d'édition (multi-curseur, flèches, Entrée, Home…).
let runtimeArmed = false
// Exécute, pour l'événement `e`, le premier binding de `editKeymap` qui matche
// (même sémantique de priorité que CodeMirror). Gère les modificateurs Mod/Alt
// et la variante `shift` des bindings. Renvoie true si une commande a agi.
function runEditKeymap(e) {
  for (const b of editKeymap) {
    if (!b.key) continue
    const parts = b.key.split('-')
    if (parts[parts.length - 1] !== e.key) continue
    if ((parts.includes('Mod') || parts.includes('Ctrl') || parts.includes('Cmd')) !== (e.ctrlKey || e.metaKey)) continue
    if (parts.includes('Alt') !== e.altKey) continue
    const cmd = (e.shiftKey && b.shift) ? b.shift : b.run
    if (cmd && cmd(view)) return true
  }
  return false
}
const onGlobalKeydown = e => {
  // Alt+Entrée : lance ou RELANCE l'exécution — géré en capture pour marcher
  // même quand le focus est sur le CANVAS (programme graphique en cours), pas
  // seulement dans l'éditeur.
  if (e.key === 'Enter' && e.altKey) {
    e.preventDefault()
    e.stopImmediatePropagation()
    relaunch()
    return
  }
  // Échap : stoppe l'exécution en cours (focus éditeur OU canvas).
  if (e.key === 'Escape' && isRunning) {
    e.preventDefault()
    e.stopImmediatePropagation()
    stopExec()
    return
  }
  if (!runtimeArmed || !view.hasFocus) return
  if (e.key !== 'Backspace' && e.key !== 'Tab') return   // seules touches mangées par GLFW
  if (runEditKeymap(e)) {
    e.preventDefault()
    e.stopImmediatePropagation()
  }
}
window.addEventListener('keydown', onGlobalKeydown, true)   // capture + avant l'écouteur GLFW
disposers.push(() => window.removeEventListener('keydown', onGlobalKeydown, true))

// ── Déplacement du curseur au glissement horizontal (tactile / mobile) ──────
// L'éditeur est en retour-à-la-ligne → aucun scroll horizontal, on utilise donc
// le glissement HORIZONTAL du doigt pour déplacer le curseur : 1 cran par
// largeur de glyphe glissée, déplacement LINÉAIRE dans le document (franchit les
// fins de ligne). Le glissement vertical reste le scroll natif.
;(function () {
  const H_THRESHOLD = 8      // px avant de trancher la direction du geste
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
      active = Math.abs(dx) > Math.abs(dy)   // horizontal → on prend la main ; vertical → scroll natif
    }
    if (!active) return
    e.preventDefault()   // on gère : pas de scroll ni de sélection native
    const cw = view.defaultCharacterWidth || 8
    const pos = Math.max(0, Math.min(view.state.doc.length, head0 + Math.round(dx / cw)))
    view.dispatch({ selection: { anchor: pos }, scrollIntoView: true })
  }, { passive: false })

  const end = () => { decided = false; active = false }
  dom.addEventListener('touchend', end, { passive: true })
  dom.addEventListener('touchcancel', end, { passive: true })
})()

// ── Barre d'aide à la saisie (symboles) — tactile uniquement ────────────────
// Insère un symbole au curseur SANS voler le focus (sinon le clavier se ferme).
// Affichée seulement sur appareil tactile, quand l'éditeur a le focus.
;(function () {
  const kbar = document.getElementById('kbar')
  if (!kbar) return
  const onDown = (e) => {
    const key = e.target.closest('.kbar-key')
    if (!key) return
    e.preventDefault()   // garde le focus de l'éditeur → le clavier reste ouvert
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

  // Affichage/masquage : tactile uniquement, et SEULEMENT quand le CLAVIER est
  // réellement ouvert. On ne se fie PAS au focus seul : au lancement, l'init fait
  // un view.focus() programmatique qui N'OUVRE PAS le clavier (iOS) → la barre ne
  // doit pas apparaître. On détecte le clavier via visualViewport (la zone visible
  // rétrécit franchement quand il s'ouvre).
  const coarse = window.matchMedia && window.matchMedia('(pointer: coarse)').matches
  if (coarse) {
    const runBtnEl = document.getElementById('run-btn')
    const vv = window.visualViewport
    // Clavier ouvert ≈ la zone visible perd > 120px par rapport au layout viewport.
    const keyboardOpen = () => (vv ? (window.innerHeight - vv.height > 120) : false)
    const update = () => {
      const editing = document.activeElement === view.contentDOM
      const running = runBtnEl && runBtnEl.classList.contains('running')
      kbar.classList.toggle('show', editing && keyboardOpen() && !running)
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
    })
  }
})()

view.focus()
window.__ollinView = view    // accès à l'éditeur pour le débogage/console (nettoyé au démontage)
// (La réouverture de la dernière vue est gérée au niveau du routeur, app.js.)

// ── Projets & fichiers ──────────────────────────────────────────────────────
// L'éditeur édite le fichier COURANT du projet ACTIF. Le menu Projet (drill-down)
// et la liste latérale de fichiers pilotent l'état. Le Run reste mono-fichier à
// cette étape (il exécute le fichier affiché) ; le multi-fichiers vient en 1.3.
const projectBtn   = document.getElementById('project-btn')
const projectLabel = document.getElementById('project-label')
const projectMenu  = document.getElementById('project-menu')
const fileRail     = document.getElementById('file-list')
const newFileBtn   = document.getElementById('new-file-btn')
const resList      = document.getElementById('res-list')
const newResBtn    = document.getElementById('new-res-btn')

let currentProject = null    // objet projet complet
let currentFile    = null    // chemin du fichier ouvert
let examples       = []      // [{name, file}] pour « Nouveau depuis un exemple »

const fileKey = id => 'ollin-pg-file:' + id           // dernier fichier ouvert / projet
const scripts = p => Object.keys(p.files).filter(f => f !== Store.MANIFEST).sort()

function setEditorText(text) {
  loadingFile = true
  // Recrée l'état complet → historique d'annulation VIERGE. Charger un fichier ne
  // doit pas être annulable (sinon Ctrl+Z vide le fichier), et chaque fichier a son
  // propre historique (sinon Ctrl+Z après changement de fichier ferait resurgir le
  // contenu du fichier précédent). setState remplace doc + historique d'un coup.
  view.setState(EditorState.create({ doc: text, extensions: editorExtensions }))
  loadingFile = false
}

function flushEditorToFile() {
  if (currentProject && currentFile)
    currentProject.files[currentFile] = view.state.doc.toString()
}

function scheduleSave() {
  if (!currentProject) return
  flushEditorToFile()
  Store.saveProject(currentProject).catch(e => console.error('saveProject', e))
}

// ── liste latérale de fichiers ──
function renderFiles() {
  fileRail.innerHTML = ''
  if (!currentProject) return
  for (const path of scripts(currentProject)) {
    const isEntry = path === currentProject.entry
    const row = document.createElement('div')
    row.className = 'file-item' + (path === currentFile ? ' active' : '')
    row.title = path
    const label = document.createElement('span')
    label.className = 'file-name'
    label.textContent = path
    if (isEntry) row.classList.add('entry')
    row.appendChild(label)

    const acts = document.createElement('span')
    acts.className = 'file-acts'
    acts.appendChild(iconBtn(isEntry ? '★' : '☆', isEntry ? 'Point d\'entrée' : 'Définir comme point d\'entrée',
      e => { e.stopPropagation(); setEntry(path) }))
    acts.appendChild(iconBtn('✎', 'Renommer', e => { e.stopPropagation(); renameFile(path) }))
    acts.appendChild(iconBtn('🗑', 'Supprimer', e => { e.stopPropagation(); deleteFile(path) }))
    row.appendChild(acts)

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
  if (path === currentFile) return
  flushEditorToFile()
  currentFile = path
  setEditorText(currentProject.files[path] ?? '')
  localStorage.setItem(fileKey(currentProject.id), path)
  renderFiles()
  view.focus()
}

async function newFile() {
  let name = prompt('Nom du nouveau fichier (.ol) :', 'nouveau.ol')
  if (!name) return
  name = name.trim()
  if (!/\.ol$/.test(name)) name += '.ol'
  if (currentProject.files[name] !== undefined) { alert('Ce fichier existe déjà.'); return }
  flushEditorToFile()
  currentProject.files[name] = ''
  await Store.saveProject(currentProject)
  openFile(name)
}

async function renameFile(path) {
  let name = prompt('Renommer le fichier :', path)
  if (!name || name.trim() === path) return
  name = name.trim()
  if (!/\.ol$/.test(name)) name += '.ol'
  if (currentProject.files[name] !== undefined) { alert('Ce nom est déjà pris.'); return }
  flushEditorToFile()
  currentProject.files[name] = currentProject.files[path]
  delete currentProject.files[path]
  if (currentProject.entry === path) currentProject.entry = name
  if (currentFile === path) currentFile = name
  await Store.saveProject(currentProject)
  localStorage.setItem(fileKey(currentProject.id), currentFile)
  setEditorText(currentProject.files[currentFile] ?? '')
  renderFiles()
}

async function deleteFile(path) {
  if (scripts(currentProject).length <= 1) { alert('Un projet doit garder au moins un fichier.'); return }
  if (!confirm(`Supprimer « ${path} » ?`)) return
  delete currentProject.files[path]
  if (currentProject.entry === path) currentProject.entry = scripts(currentProject)[0]
  if (currentFile === path) currentFile = currentProject.entry
  await Store.saveProject(currentProject)
  setEditorText(currentProject.files[currentFile] ?? '')
  renderFiles()
}

async function setEntry(path) {
  currentProject.entry = path
  await Store.saveProject(currentProject)
  renderFiles()
}

// ── ressources (images) ──
function renderResources() {
  resList.innerHTML = ''
  if (!currentProject) return
  const names = Object.keys(currentProject.resources || {}).sort()
  if (!names.length) {
    const d = document.createElement('div'); d.className = 'rail-empty'; d.textContent = '(aucune)'
    resList.appendChild(d); return
  }
  for (const name of names) {
    const row = document.createElement('div')
    row.className = 'file-item'; row.title = name
    const label = document.createElement('span'); label.className = 'file-name'; label.textContent = name
    row.appendChild(label)
    const acts = document.createElement('span'); acts.className = 'file-acts'
    acts.appendChild(iconBtn('✎', 'Renommer', e => { e.stopPropagation(); renameResource(name) }))
    acts.appendChild(iconBtn('🗑', 'Supprimer', e => { e.stopPropagation(); deleteResource(name) }))
    row.appendChild(acts)
    resList.appendChild(row)
  }
}

async function renameResource(name) {
  let n = prompt('Renommer la ressource :', name)
  if (!n || n.trim() === name) return
  n = n.trim()
  if (currentProject.resources[n] !== undefined) { alert('Ce nom est déjà pris.'); return }
  currentProject.resources[n] = currentProject.resources[name]
  delete currentProject.resources[name]
  await Store.saveProject(currentProject)
  if (ollin && ollin.preloadImage) {
    const r = currentProject.resources[n]
    ollin.preloadImage(n, r.b64, r.ext)
  }
  renderResources()
}

async function deleteResource(name) {
  if (!confirm(`Supprimer la ressource « ${name} » ?`)) return
  delete currentProject.resources[name]
  await Store.saveProject(currentProject)
  renderResources()
}


// ── chargement / bascule de projet ──
async function loadProject(id) {
  const p = await Store.getProject(id)
  if (!p) return
  removeExampleBanner()   // quitte le mode exemple
  flushEditorToFile()
  currentProject = p
  Store.setActiveId(id)
  const files = scripts(p)
  const last = localStorage.getItem(fileKey(id))
  currentFile = (last && p.files[last] !== undefined) ? last
              : (p.files[p.entry] !== undefined ? p.entry : files[0])
  setEditorText(p.files[currentFile] ?? '')
  projectLabel.textContent = p.name
  renderFiles()
  renderResources()
  view.focus()
  // Éteindre la pastille du projet précédent AVANT le contrôle async : sinon,
  // pour un projet sans lien distant (ou hors-ligne), checkRemoteFreshness sort
  // sans toucher la pastille → elle resterait allumée à tort sur ce projet.
  projectBtn.classList.remove('sync-update')
  checkRemoteFreshness(p)   // garde-fou d'ouverture (non bloquant)
}

async function switchProject(id) {
  if (currentProject) {                       // en mode exemple il n'y a rien à sauver
    flushEditorToFile()                       // récupérer les dernières frappes
    await Store.saveProject(currentProject)   // puis persister avant de quitter
  }
  await loadProject(id)
}

// Ouvre un projet depuis le menu. En MODE EXEMPLE (aucun projet courant), on quitte
// le mode par une NAVIGATION (comme forkExampleToProject) → re-montage propre en mode
// projet et URL correcte (un refresh rouvre le projet, pas l'exemple). Sinon, bascule
// en place. Corrige : en mode sample, ouvrir/créer un projet ne montrait rien alors
// que le projet était bien créé (visible seulement après relance de l'app).
async function openProject(id) {
  if (exampleFile) {
    Store.setActiveId(id)
    ctx.navigate('playground')
  } else {
    await switchProject(id)
  }
}

// ── menu Projet (drill-down) ──
function closeMenu() {
  projectMenu.style.display = 'none'
  projectBtn.setAttribute('aria-expanded', 'false')
}
function openMenu() {
  renderMenuRoot()
  projectMenu.style.display = 'block'
  projectBtn.setAttribute('aria-expanded', 'true')
}
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
    b.title = 'Retour'
    b.addEventListener('click', back)
    h.appendChild(b)
  }
  const s = document.createElement('span')
  s.textContent = text
  h.appendChild(s)
  return h
}
function menuSep() {
  const d = document.createElement('div')
  d.className = 'menu-sep'
  return d
}

function renderMenuRoot() {
  projectMenu.innerHTML = ''
  projectMenu.appendChild(menuHeader('Projet : ' + (currentProject ? currentProject.name : '—')))
  projectMenu.appendChild(menuItem('📂 Ouvrir un projet', true, renderMenuOpen))
  projectMenu.appendChild(menuItem('✨ Nouveau projet vide', false, async () => {
    const name = prompt('Nom du projet :', 'Sans titre'); if (!name) return
    const p = await Store.createProject(name.trim()); closeMenu(); await openProject(p.id)
  }))
  projectMenu.appendChild(menuItem('📄 Ouvrir un exemple', true, renderMenuExamples))
  // Actions sur le PROJET COURANT : masquées en mode exemple (currentProject null,
  // rien à renommer/dupliquer/supprimer) — sinon elles planteraient sur null.
  if (currentProject) {
    projectMenu.appendChild(menuSep())
    projectMenu.appendChild(menuItem('✎ Renommer', false, async () => {
      const name = prompt('Nouveau nom :', currentProject.name); if (!name) return
      flushEditorToFile(); await Store.saveProject(currentProject)
      const p = await Store.renameProject(currentProject.id, name.trim())
      closeMenu(); await loadProject(p.id)
    }))
    projectMenu.appendChild(menuItem('⧉ Dupliquer', false, async () => {
      flushEditorToFile(); await Store.saveProject(currentProject)
      const copy = await Store.createProject(currentProject.name + ' (copie)')
      copy.files = { ...currentProject.files }; copy.entry = currentProject.entry
      delete copy.files[Store.MANIFEST]
      await Store.saveProject(copy)
      closeMenu(); await switchProject(copy.id)
    }))
    projectMenu.appendChild(menuItem('🗑 Supprimer', false, async () => {
      if (!confirm(`Supprimer le projet « ${currentProject.name} » ?`)) return
      const gone = currentProject.id
      await Store.deleteProject(gone)
      const list = await Store.listProjects()
      closeMenu()
      if (list.length) await loadProject(list[0].id)
      else { const p = await Store.createProject('Sans titre'); await loadProject(p.id) }
    }))
  }

  // ── section GitHub ──
  projectMenu.appendChild(menuSep())
  if (GH.isConnected()) {
    const hdr = document.createElement('div')
    hdr.className = 'menu-header'
    hdr.textContent = 'GitHub' + (ghLogin ? ' : @' + ghLogin : '')
    projectMenu.appendChild(hdr)
    if (!ghLogin) {
      GH.getUser().then(u => { ghLogin = u.login; hdr.textContent = 'GitHub : @' + u.login }).catch(() => {})
    }
    projectMenu.appendChild(menuItem('🗄 Dépôt : ' + GH.getRepo(), false, () => {
      const v = prompt('Dépôt cible (nom, ou « owner/repo » pour un dépôt partagé) :', GH.getRepo())
      if (v === null) return
      GH.setRepo(v)
      renderMenuRoot()
    }))
    if (currentProject) {   // pousser/récupérer agit sur le projet courant (nul en mode exemple)
      projectMenu.appendChild(menuItem('⬆ Pousser vers GitHub', false, () => ghPush()))
      projectMenu.appendChild(menuItem('⬇ Récupérer (Pull)', false, ghPull))
    }
    projectMenu.appendChild(menuItem('📥 Ouvrir depuis GitHub', true, renderMenuRemote))
    projectMenu.appendChild(menuItem('⏻ Déconnexion', false, () => { GH.clearToken(); ghLogin = null; renderMenuRoot() }))
  } else {
    projectMenu.appendChild(menuItem('🔗 Se connecter à GitHub', true, renderMenuConnect))
  }
}

async function renderMenuOpen() {
  const list = await Store.listProjects()
  projectMenu.innerHTML = ''
  projectMenu.appendChild(menuHeader('Ouvrir un projet', renderMenuRoot))
  for (const p of list) {
    const check = (currentProject && p.id === currentProject.id) ? '✓ ' : ''
    projectMenu.appendChild(menuItem(check + p.name, false, async () => {
      closeMenu()
      if (!currentProject || p.id !== currentProject.id) await openProject(p.id)
    }))
  }
}

function renderMenuExamples() {
  projectMenu.innerHTML = ''
  projectMenu.appendChild(menuHeader('Ouvrir un exemple', renderMenuRoot))
  if (!examples.length) {
    const d = document.createElement('div'); d.className = 'menu-empty'; d.textContent = 'Aucun exemple.'
    projectMenu.appendChild(d); return
  }
  // Ouvre l'exemple en LECTURE DIRECTE depuis le dépôt (route #/playground/
  // sample/<fichier>) : pas de copie, un refresh recharge la version du dépôt.
  // Pour garder/éditer, le bandeau propose « Créer un projet ».
  for (const ex of examples) {
    projectMenu.appendChild(menuItem('📄 ' + ex.name, false, () => {
      closeMenu()
      ctx.navigate('playground', 'sample/' + ex.file)
    }))
  }
}

// ── GitHub : état + parcours ──────────────────────────────────────────────
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

function renderMenuConnect() {
  projectMenu.innerHTML = ''
  projectMenu.appendChild(menuHeader('Se connecter à GitHub', renderMenuRoot))
  const wrap = document.createElement('div'); wrap.className = 'menu-form'
  const info = document.createElement('div'); info.className = 'menu-info'
  info.innerHTML = 'Colle un <b>fine-grained token</b> (dépôt <code>ollin-projects</code>, permission Contents : lecture/écriture). '
    + '<a href="https://github.com/settings/personal-access-tokens/new" target="_blank" rel="noopener">Créer un token ↗</a>'
  const input = document.createElement('input')
  input.type = 'password'; input.className = 'menu-input'; input.placeholder = 'github_pat_… / ghp_…'
  const repo = document.createElement('input')
  repo.type = 'text'; repo.className = 'menu-input'; repo.value = GH.getRepo()
  repo.placeholder = 'dépôt : ollin-projects ou owner/repo'
  repo.title = 'Dépôt cible (défaut ollin-projects). « owner/repo » pour un dépôt partagé.'
  const btn = document.createElement('button'); btn.className = 'menu-btn'; btn.textContent = 'Connecter'
  const err = document.createElement('div'); err.className = 'menu-err'
  const connect = async () => {
    const t = input.value.trim(); if (!t) return
    GH.setToken(t); GH.setRepo(repo.value); btn.disabled = true; btn.textContent = 'Vérification…'; err.textContent = ''
    try { const u = await GH.getUser(); ghLogin = u.login; renderMenuRoot() }
    catch (e) { GH.clearToken(); err.textContent = 'Token invalide : ' + e.message; btn.disabled = false; btn.textContent = 'Connecter' }
  }
  btn.addEventListener('click', connect)
  input.addEventListener('keydown', e => { if (e.key === 'Enter') connect() })
  repo.addEventListener('keydown', e => { if (e.key === 'Enter') connect() })
  wrap.append(info, input, repo, btn, err)
  projectMenu.appendChild(wrap)
  input.focus()
}

async function ghPush(force) {
  closeMenu()
  if (!currentProject) return
  flushEditorToFile(); await Store.saveProject(currentProject)
  setStatus('Envoi vers GitHub…')
  try {
    await GH.ensureRepo()
    await GH.pushProject(currentProject, null, { force })
    await Store.saveProject(currentProject)   // persister project.remote (dont folderSha)
    projectBtn.classList.remove('sync-update')   // on est à jour
    setStatus('Poussé sur GitHub ✓', true)
  } catch (e) {
    if (e.code === 'CONFLICT') {
      if (confirm('Le dépôt distant a été modifié depuis ta dernière synchro (sans doute depuis un autre poste).\n\nÉcraser avec ta version locale ?\nOK = écraser · Annuler = ne rien faire (fais « Récupérer / Pull » d\'abord).')) {
        return ghPush(true)
      }
      setStatus('Push annulé — fais « Récupérer (Pull) » d\'abord', true)
      return
    }
    setStatus('Erreur : ' + e.message, true, true)
  }
}

// Cœur du Pull (sans confirmation) — réutilisé par ghPull et le garde-fou d'ouverture.
async function doPull() {
  if (!currentProject) return
  const slug = (currentProject.remote && currentProject.remote.slug) || currentProject.id
  setStatus('Récupération…')
  try {
    const p = await GH.pullProject(slug)
    p.id = currentProject.id
    await Store.saveProject(p)
    await loadProject(p.id)
    setStatus('Projet à jour ✓', true)
  } catch (e) { setStatus('Erreur : ' + e.message, true, true) }
}

async function ghPull() {
  closeMenu()
  if (!currentProject) return
  const slug = (currentProject.remote && currentProject.remote.slug) || currentProject.id
  if (!confirm(`Récupérer « ${slug} » depuis GitHub et remplacer la version locale ?`)) return
  await doPull()
}

// Garde-fou d'ouverture : à l'ouverture d'un projet lié à GitHub (connecté),
// vérifie en arrière-plan si une version plus récente existe et propose un Pull.
// PASSIF : aucune boîte de dialogue, aucun Pull automatique. On se contente
// d'un message discret ; l'utilisateur garde le contrôle (Pull manuel au besoin).
async function checkRemoteFreshness(project) {
  if (!project.remote || !project.remote.slug || !GH.isConnected()) return
  try {
    const cur = await GH.remoteFolderSha(project.remote.slug)
    if (!currentProject || currentProject.id !== project.id) return   // projet changé entre-temps
    // Base de comparaison = SHA du tree du dossier lu lors de notre dernier
    // push/pull. On ne signale QUE si l'on a une base fiable (known) ET qu'elle
    // diffère du distant. Sans base connue (jamais synchro avec cette version),
    // on reste SILENCIEUX : la pastille n'est qu'un rappel, pas une alerte —
    // mieux vaut ne rien afficher qu'un faux positif.
    const known = (project.remote && project.remote.folderSha) || null
    // Même règle que le garde-fou de conflit (GH.folderMoved), + politique
    // pastille : muette si pas de base connue (rappel, pas alerte).
    const newer = known !== null && GH.folderMoved(cur, known)
    projectBtn.classList.toggle('sync-update', newer)   // pastille persistante
    if (newer) setStatus('⬇ Version plus récente sur GitHub — « Récupérer (Pull) » pour l\'obtenir')
  } catch (_) { /* hors-ligne / token invalide : silencieux */ }
}

async function renderMenuRemote() {
  projectMenu.innerHTML = ''
  projectMenu.appendChild(menuHeader('Ouvrir depuis GitHub', renderMenuRoot))
  const loading = document.createElement('div'); loading.className = 'menu-empty'; loading.textContent = 'Chargement…'
  projectMenu.appendChild(loading)
  let list
  try { list = await GH.listRemoteProjects() }
  catch (e) { loading.textContent = 'Erreur : ' + e.message; return }
  loading.remove()
  if (!list.length) {
    const d = document.createElement('div'); d.className = 'menu-empty'; d.textContent = 'Aucun projet distant.'
    projectMenu.appendChild(d); return
  }
  for (const r of list) {
    projectMenu.appendChild(menuItem('📦 ' + r.name, false, async () => {
      closeMenu()
      const existing = await Store.getProject(r.slug)
      if (existing && !confirm(`Un projet « ${r.slug} » existe déjà en local. L'écraser avec la version GitHub ?`)) return
      flushEditorToFile()
      if (currentProject && currentProject.id !== r.slug) await Store.saveProject(currentProject)
      setStatus('Récupération…')
      try {
        const p = await GH.pullProject(r.slug)
        await Store.saveProject(p)
        await loadProject(p.id)
        setStatus('Projet ouvert ✓', true)
      } catch (e) { setStatus('Erreur : ' + e.message, true, true) }
    }))
  }
}

projectBtn.addEventListener('click', e => {
  e.stopPropagation()
  if (projectMenu.style.display === 'block') closeMenu(); else openMenu()
})
// Les clics DANS le menu ne remontent pas au document : sinon, quand un item
// reconstruit le menu (innerHTML=''), sa cible est détachée et le test
// « clic à l'extérieur » ci-dessous fermerait le menu par erreur (drill-down).
projectMenu.addEventListener('click', e => e.stopPropagation())
const onDocClick = e => {
  if (projectMenu.style.display === 'block' && !projectMenu.contains(e.target) && e.target !== projectBtn)
    closeMenu()
}
document.addEventListener('click', onDocClick)
disposers.push(() => document.removeEventListener('click', onDocClick))
newFileBtn.addEventListener('click', newFile)

// ── bascule de la barre latérale (état NON mémorisé : fermée à chaque ouverture) ──
const railToggle = document.getElementById('rail-toggle')
const fileRailEl = document.getElementById('file-rail')
// La barre des fichiers démarre TOUJOURS fermée à l'ouverture de l'éditeur ;
// le bouton l'ouvre/ferme pour la session en cours (pas de persistance).
let railHidden = true
function applyRail() {
  fileRailEl.classList.toggle('rail-hidden', railHidden)
  railToggle.classList.toggle('active', !railHidden)
  railToggle.setAttribute('aria-pressed', String(!railHidden))
}
const onRailToggle = () => {
  railHidden = !railHidden
  applyRail()
}
railToggle.addEventListener('click', onRailToggle)
disposers.push(() => railToggle.removeEventListener('click', onRailToggle))
applyRail()

// ── Mode exemple : lecture directe depuis le dépôt (sans copie) ─────────────
// Bandeau au-dessus de l'éditeur signalant que rien n'est enregistré, avec un
// bouton pour forker en projet éditable.
function removeExampleBanner() {
  const b = document.getElementById('example-banner')
  if (b) b.remove()
}
function showExampleBanner(file) {
  removeExampleBanner()
  const bar = document.createElement('div')
  bar.id = 'example-banner'
  bar.style.cssText = 'display:flex;align-items:center;gap:10px;padding:6px 12px;background:#1e2133;border-bottom:1px solid #2e3150;font-size:12px;color:#a9b2cf'
  const txt = document.createElement('span')
  txt.innerHTML = '📄 Exemple <b style="color:#c9d1e0">' + file + '</b> — non enregistré (un rafraîchissement recharge la version du dépôt)'
  const btn = document.createElement('button')
  btn.textContent = 'Créer un projet'
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
  // ctx.v change à chaque chargement de page → un refresh re-fetch la version
  // fraîche. fetchSample rejette sur 404 (pas de page d'erreur chargée en douce).
  let code
  try {
    code = await Run.fetchSample(file, ctx.v)
  } catch (e) {
    removeExampleBanner()
    setEditorText('## ' + (e && e.message ? e.message : 'exemple introuvable : ' + file))
    setStatus('Exemple introuvable : ' + file, true, true)
    return
  }
  setEditorText(code)
  showExampleBanner(file)
  const label = document.getElementById('project-label')
  if (label) label.textContent = file
}

// Fork explicite : convertit l'exemple affiché en projet éditable persistant.
async function forkExampleToProject(file) {
  const name = prompt('Nom du projet :', file.replace(/\.ol$/, ''))
  if (!name) return
  const p = await Store.createProject(name.trim())
  p.files[p.entry] = view.state.doc.toString()
  await Store.saveProject(p)
  Store.setActiveId(p.id)
  ctx.navigate('playground')   // quitte le mode exemple → re-montage en mode projet
}

// ── init ──
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

// ── Output ────────────────────────────────────────────────────────────────
const outputEl   = document.getElementById('output')
const canvasEl   = document.getElementById('canvas')
const outputPane = document.getElementById('output-pane')
const dividerEl  = document.getElementById('divider')
const outputHdr  = document.getElementById('output-header')

// Le canvas est PARTAGÉ (rangé dans le shell hors exécution). On le reparente
// dans la zone de rendu de cette vue ; app.js le range à nouveau au démontage.
canvasEl.style.display = 'none'
outputPane.appendChild(canvasEl)

// La zone de rendu (sortie + canvas) n'apparaît qu'en exécution/pause ;
// au repos l'éditeur occupe TOUT l'espace.
function setOutputVisible(visible) {
  outputPane.style.display = visible ? '' : 'none'
  if (dividerEl) dividerEl.style.display = visible ? '' : 'none'
  if (visible) {
    restoreSplit()                       // rétablir le découpage choisi
  } else {
    // éditeur plein écran : retirer les bases flex fixes posées par le drag
    editorPane.style.flex = ''
    outputPane.style.flex = ''
  }
}

const runBtn   = document.getElementById('run-btn')
const stopBtn  = document.getElementById('stop-btn')
let   isRunning = false
let   isPaused  = false

const ICON_RUN   = '<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><path d="M3 2l11 6-11 6V2z"/></svg>'
const ICON_STOP  = '<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><rect x="2" y="2" width="12" height="12" rx="2"/></svg>'
const ICON_PAUSE = '<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><rect x="2" y="2" width="4" height="12" rx="1"/><rect x="10" y="2" width="4" height="12" rx="1"/></svg>'
const ICON_RESUME= '<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><path d="M3 2l11 6-11 6V2z"/></svg>'

function setRunning(running) {
  isRunning = running
  if (running) {
    runBtn.classList.add('running')
    runBtn.innerHTML = ICON_STOP + '<span class="btn-label"> Arrêter</span>'
    stopBtn.style.display = 'flex'
    stopBtn.disabled = false
    document.getElementById('kbar')?.classList.remove('show')   // pas d'aide à la saisie pendant l'exécution
  } else {
    runBtn.classList.remove('running')
    runBtn.innerHTML = ICON_RUN + '<span class="btn-label"> Exécuter</span><kbd>Ctrl+↵</kbd>'
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
  outputPane.style.overflow = ''
  setRunning(false)
  setOutputVisible(false)   // retour éditeur plein écran
}

function showOutput(text) {
  canvasEl.style.display = 'none'
  outputEl.style.display = 'block'
  if (outputHdr) outputHdr.style.display = 'flex'
  outputPane.style.overflow = ''
  if (!text) {
    outputEl.textContent = '(aucune sortie)'
    outputEl.className   = ''
  } else if (text.startsWith('error:')) {
    outputEl.className = 'err'
    renderErrorWithLink(text)
  } else {
    outputEl.textContent = text
    outputEl.className   = 'ok'
  }
}

// Extrait la localisation d'un message « error: [<fichier>: ]line N: … » (syntaxe
// lex/parse OU runtime VM). Renvoie { file?, line, str, index } où `str`/`index`
// repèrent la sous-chaîne à rendre cliquable ; null si aucune ligne.
function errLoc(text) {
  const m = /(?:([\w./-]+\.ol)\s*:\s*)?line\s+(\d+)/.exec(text || '')
  if (!m) return null
  return { file: m[1] || null, line: parseInt(m[2], 10), str: m[0], index: m.index }
}

// Affiche l'erreur dans la zone de sortie ; la portion « fichier:ligne » devient
// un LIEN cliquable qui amène à la ligne fautive (pas de saut automatique).
function renderErrorWithLink(text) {
  const loc = errLoc(text)
  if (!loc) { outputEl.textContent = text; return }
  outputEl.textContent = ''
  outputEl.appendChild(document.createTextNode(text.slice(0, loc.index)))
  const link = document.createElement('span')
  link.className = 'err-link'
  link.textContent = loc.str
  link.title = 'Aller à la ligne fautive'
  link.addEventListener('click', () => gotoError(loc))
  outputEl.appendChild(link)
  outputEl.appendChild(document.createTextNode(text.slice(loc.index + loc.str.length)))
}

// Ouvre le fichier fautif si besoin et positionne le curseur sur la ligne
// (sélectionnée → surlignée jusqu'à la prochaine frappe). Appelé au CLIC du lien.
function gotoError(loc) {
  if (!loc) return
  let file = loc.file
  // Résout le fichier nommé (chemin de l'import) vers une clé du projet : match
  // exact, sinon par nom de base (les clés projet peuvent différer du résolu).
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

// ── Run ───────────────────────────────────────────────────────────────────
let ollin = null

// Démarre l'exécution (à froid). Ne toggle pas : voir run()/relaunch()/stopExec().
async function launch() {
  if (!ollin) return
  try { ollin.pauseMainLoop() } catch(_) {}
  setRunning(false)
  outputEl.className = ''
  // Afficher la zone AVANT execute : window.width lit le clientWidth de
  // #output-pane (0 si display:none → graphics dimensionné à vide).
  setOutputVisible(true)
  flushEditorToFile()
  // Préchargement + exécution + gestion d'erreurs : logique PARTAGÉE avec le mode
  // autonome (run.html) via pg-run.js — plus de duplication ni de divergence.
  Run.loadProjectIntoRuntime(ollin, currentProject)
  const code = currentProject ? (currentProject.files[currentProject.entry] ?? '')
                              : view.state.doc.toString()
  // Mode exemple/brouillon : modèles 3D référencés (graphics.model("x.obj"))
  // préchargés depuis samples/ (les projets utilisateur passent par leurs ressources).
  if (!currentProject) {
    const imported = await Run.preloadSampleImports(ollin, code, ctx.v)
    await Run.preloadSampleModels(ollin, code + '\n' + imported, ctx.v)   // modèles des imports aussi
  }
  Run.runProgram(ollin, code, canvasEl, {
    onError:   (msg) => { setRunning(false); showOutput(msg) },
    onRunning: () => {
      outputPane.style.overflow = 'hidden'
      if (outputHdr) outputHdr.style.display = 'none'
      runtimeArmed = true   // GLFW a installé son écouteur clavier global (Backspace/Tab)
      setRunning(true)
    },
    onOutput:  (out) => showOutput(out),
  })
}

// Bouton Exécuter : bascule (le bouton affiche « Arrêter » pendant l'exécution).
function run() {
  if (!ollin) return
  if (isRunning) { clearAndStop(); return }
  launch()
}

// Alt+Entrée : lance, ou RELANCE à froid si déjà en cours.
function relaunch() {
  if (!ollin) return
  if (isRunning) clearAndStop()
  launch()
}

// Échap : arrête l'exécution en cours (sinon sans effet).
function stopExec() {
  if (isRunning) clearAndStop()
}

runBtn.addEventListener('click', run)
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

// ── Formater ────────────────────────────────────────────────────────────────
// Réindente le code (pg-format.js) à la demande. Ne change QUE l'indentation, et
// préserve le curseur (même ligne + colonne dans le contenu). S'abstient si les
// blocs sont déséquilibrés (message d'erreur, aucune modification).
function doFormat() {
  const r = Fmt.formatOllin(view.state.doc.toString())
  if (!r.ok) { setStatus('Formatage impossible : ' + r.error, true, true); return }
  if (r.code === view.state.doc.toString()) { setStatus('Déjà formaté ✓', true); return }
  const head = view.state.selection.main.head
  const oldLine = view.state.doc.lineAt(head)
  const contentCol = Math.max(0, head - oldLine.from - (oldLine.text.length - oldLine.text.trimStart().length))
  const ln = oldLine.number
  view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: r.code } })
  const nl = view.state.doc.line(Math.min(ln, view.state.doc.lines))   // même n° de ligne (nombre préservé)
  const newIndent = nl.text.length - nl.text.trimStart().length
  view.dispatch({ selection: { anchor: Math.min(nl.from + newIndent + contentCol, nl.to) }, scrollIntoView: true })
  view.focus()
  setStatus('Code formaté ✓', true)
}
document.getElementById('format-btn').addEventListener('click', doFormat)

// ── Copy ──────────────────────────────────────────────────────────────────
const copyBtn = document.getElementById('copy-btn')
const ICON_COPY = ICONS.copy   // partagés (cm-shared.js)
const ICON_OK   = ICONS.ok
copyBtn.addEventListener('click', () => {
  navigator.clipboard.writeText(view.state.doc.toString()).then(() => {
    copyBtn.innerHTML = ICON_OK + '<span class="btn-label"> Copié !</span>'
    copyBtn.style.color        = 'var(--green)'
    copyBtn.style.borderColor  = 'var(--green)'
    setTimeout(() => {
      copyBtn.innerHTML = ICON_COPY + '<span class="btn-label"> Copier</span>'
      copyBtn.style.color = ''
      copyBtn.style.borderColor = ''
    }, 1500)
  })
})

// ── Mode autonome (vue plein écran, nouvel onglet) ──────────────────────────
// Ouvre la vue #/run dans un nouvel onglet (page dédiée plein écran). Le projet
// complet (fichiers + ressources) est persisté dans IndexedDB ; on ne partage
// que l'id du projet actif — la vue #/run le recharge depuis là. IndexedDB (pas
// localStorage, limité à ~5 Mo → une image ≥ 4 Mo faisait échouer l'écriture en
// silence, d'où « aucun projet »).
const standaloneBtn = document.getElementById('standalone-btn')
standaloneBtn.addEventListener('click', () => {
  // Onglet ouvert SYNCHRONEMENT (conserve le user gesture → pas bloqué par le
  // pop-up blocker), mais on n'y charge #/run qu'APRÈS que le projet soit COMMITÉ
  // dans IndexedDB (sinon l'autre onglet pourrait lire une version périmée, voire
  // « aucun projet » pour un projet neuf). saveProject est donc bien attendu.
  const win = window.open('', '_blank')
  ;(async () => {
    let target = 'index.html#/run'
    if (exampleFile) {
      // Mode exemple : exécute le MÊME exemple frais en autonome (pas de projet).
      target = 'index.html#/run/sample/' + exampleFile
    } else {
      try {
        flushEditorToFile()
        if (currentProject) {
          Store.setActiveId(currentProject.id)
          await Store.saveProject(currentProject)
        }
      } catch (_) {}
    }
    const url = Run.freshUrl(target)
    if (win && !win.closed) win.location.replace(url)
    else window.open(url, '_blank')   // repli si l'onglet a été bloqué
  })()
})

// ── Recharger + vider le cache ──────────────────────────────────────────────
// Vide le Cache API puis recharge (le code de l'éditeur est conservé dans
// localStorage). Utile pour récupérer un WASM fraîchement déployé.
const reloadBtn = document.getElementById('reload-btn')
reloadBtn.addEventListener('click', hardReload)   // rechargement dur partagé (pg-run.js via ctx)

// ── Image upload ──────────────────────────────────────────────────────────
// Les images sont gérées UNIQUEMENT via la section « Ressources » du rail (comme
// les fichiers) : le « ＋ » ouvre ce sélecteur (masqué). Pas de bouton dédié dans
// la barre d'outils — cohérent avec les fichiers, et les ressources sont moins
// utilisées.
const imgFileInput = document.getElementById('img-file-input')

// Les images chargées deviennent des RESSOURCES du projet actif (persistées).
imgFileInput.addEventListener('change', () => {
  const files = Array.from(imgFileInput.files)
  if (!files.length || !currentProject) return
  files.forEach(file => {
    const ext  = file.name.split('.').pop().toLowerCase()
    const name = file.name
    const reader = new FileReader()
    reader.onload = async e => {
      const b64 = (e.target.result.split(',')[1]) ?? ''   // "data:...;base64,xxxx"
      currentProject.resources[name] = { b64, ext }
      await Store.saveProject(currentProject)
      if (ollin) {
        // Modèles 3D → preloadModel ; images → preloadImage.
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

// Le « ＋ » de la section Ressources ouvre le même sélecteur de fichiers.
newResBtn.addEventListener('click', () => imgFileInput.click())

// ── WASM ──────────────────────────────────────────────────────────────────
const statusEl = document.getElementById('status')

// Runtime WASM PARTAGÉ (chargé une fois par app.js, réutilisé par toutes les
// vues). Il est déjà lié au <canvas> partagé du shell.
getOllin().then(m => {
  ollin              = m
  runBtn.disabled    = false
  statusEl.textContent = 'Prêt ✓'
  setTimeout(() => { statusEl.textContent = '' }, 2000)
}).catch(err => {
  statusEl.textContent = 'Erreur WASM : ' + (err?.message ?? err)
})

// ── Divider resize ────────────────────────────────────────────────────────
const divider    = document.getElementById('divider')
const editorPane = document.getElementById('editor-pane')
let   dragging   = false

const SPLIT_KEY = 'ollin-pg-split'

function applySplit(pct) {
  editorPane.style.flex = `0 0 ${pct}%`
  outputPane.style.flex = `0 0 ${100 - pct}%`
}

// Rétablit le découpage sauvegardé (appelé quand la zone de rendu réapparaît).
// Au repos (zone masquée) on ne pose AUCUN flex → l'éditeur remplit tout.
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

// Quitter la vue pendant une exécution graphique : mettre en pause la boucle
// raylib (sinon elle continuerait de tourner sur un canvas détaché), désarmer
// l'interception clavier, DÉTRUIRE l'éditeur CM6 (retire ses observers/listeners
// globaux → pas de fuite à chaque re-visite) et libérer la référence de debug.
disposers.push(() => {
  try { ollin && ollin.pauseMainLoop() } catch (_) {}
  runtimeArmed = false
  try { view.destroy() } catch (_) {}
  if (window.__ollinView === view) window.__ollinView = undefined
})

return () => { for (const d of disposers) d() }
}
