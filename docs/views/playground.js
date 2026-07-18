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
  search, searchKeymap, highlightSelectionMatches,
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
  // Taille de base = version NAVIGATEUR (13px). Le mobile la redéfinit
  // (playground.html, @media max-width:640px → 12px, anti-zoom iOS).
  '&': { background: '#000000', color: '#c9d1e0', fontSize: '13px', height: '100%' },
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

  /* panneau de recherche (Ctrl+F) accordé au thème sombre */
  // fontSize: inherit → toute la barre suit la taille de fonte de l'éditeur (13px
  // navigateur / 12px mobile) ; la hauteur des champs en découle. Largeur laissée par défaut.
  '.cm-panels': { background: '#1a1d2e', color: '#c9d1e0', fontSize: 'inherit' },
  '.cm-panels.cm-panels-top': { borderBottom: '1px solid #2e3150' },
  '.cm-search': { padding: '8px' },
  '.cm-search label': { color: '#7c85a2' },
  '.cm-textfield': { background: '#0f1117', color: '#c9d1e0', border: '1px solid #2e3150', borderRadius: '4px', fontSize: 'inherit', padding: '3px 6px' },
  '.cm-button': { background: '#242742', color: '#c9d1e0', border: '1px solid #2e3150', borderRadius: '4px', backgroundImage: 'none', fontSize: 'inherit' },
  '.cm-button:hover': { background: '#2d3259' },
  '.cm-panel.cm-search [name=close]': { color: '#7c85a2', fontSize: '18px', padding: '0 8px' },
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
  fn('typeof', 'typeof(v) → string'),   fn('Color', 'Color(gris | r, g, b [, a])'),
  fn('len',    'len(v) → int'),         fn('mem',    'mem() → int (octets utilisés)'),
]

// Globales injectées par le moteur (disponibles sans déclaration) — cf. CLAUDE.md.
const glob = (label, detail) => ({ label, type: 'variable', detail })
const AC_GLOBALS = [
  glob('deltaTime',   'moteur — secondes depuis la frame précédente'),
  glob('elapsedTime', 'moteur — secondes depuis le démarrage'),
  glob('W',  'moteur — largeur de la zone de rendu'),
  glob('H',  'moteur — hauteur de la zone de rendu'),
  glob('CW', 'moteur — centre X (W / 2)'),
  glob('CH', 'moteur — centre Y (H / 2)'),
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
    fn('graphics.clear','clear([color]) — alpha<1 = fondu'),
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
    fn('graphics.drawText','drawText(text,x,y,size[,color])'),
    fn('graphics.fps','fps()→int'),                fn('graphics.isOpen','isOpen()→bool'),
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
    fn('image.getPixel','getPixel(img, x, y) → color'),
    fn('image.beginPixels','beginPixels(img)'),
    fn('image.endPixels','endPixels(img)'),
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
      // On veut l'ordre ALPHABÉTIQUE (CM classe par « pertinence floue » sinon →
      // ordre déroutant) MAIS en gardant le filtrage CM (donc le surlignage gras de
      // la sous-chaîne matchée). Levier : le tri CM se fait sur `score + boost` ; on
      // pose un `boost` dominant, décroissant selon le rang alphabétique → l'ordre
      // devient alphabétique, et le surlignage (issu du filtrage CM) est conservé.
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
    options: [AC_FUNC, ...AC_LIFECYCLE, ...AC_KEYWORDS, ...AC_BUILTINS, ...AC_GLOBALS, ...moduleNames],
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
let autoexecTimer = null  // mode Auto : relance différée après la dernière modif
let loadingFile = false   // true pendant un chargement programmatique → pas d'autosave

// Tab sur un CURSEUR SIMPLE : insère des espaces jusqu'au prochain multiple de 4
// (tab stop) À LA POSITION DU CURSEUR — pas d'indentation de ligne. Sur une
// sélection, renvoie false → indentWithTab prend le relais (indente le bloc ;
// Maj+Tab désindente).
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

// Keymap de l'éditeur, gardé en référence : réutilisé tel quel par le garde-fou
// clavier « pendant un run » (voir plus bas) pour déléguer aux VRAIES commandes
// CodeMirror au lieu de les réimplémenter.
// Tab : accepte une complétion si popup, sinon insère au curseur (softTab), sinon
// (sélection) indente le bloc. closeBracketsKeymap ensuite : Backspace supprime
// une paire vide «()» d'un coup.
const editKeymap = [{ key: 'Tab', run: acceptCompletion }, { key: 'Tab', run: softTab }, ...closeBracketsKeymap, ...completionKeymap, indentWithTab, ...defaultKeymap, ...historyKeymap, ...foldKeymap]

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
      // Recherche CodeMirror : Ctrl+F ouvre le panneau et scanne TOUT le document (le
      // modèle, pas le DOM — CM ne rend que les lignes visibles, donc la recherche
      // native du navigateur manquait le reste du fichier). highlightSelectionMatches
      // surligne les autres occurrences du mot sélectionné.
      search({ top: true }), highlightSelectionMatches(),
      keymap.of(editKeymap),
      keymap.of([
        { key: 'Alt-Enter', run: () => { relaunch(); return true } },   // lance / relance
        { key: 'Escape', run: () => { if (isRunning) { stopExec(); return true } return false } },
        { key: 'Shift-Alt-f', run: () => { doFormat(); return true } },   // reformater
        // F4 : aller à la première erreur de syntaxe/exécution (lien de la zone sortie).
        { key: 'F4', run: () => { if (lastErrorLoc) { gotoError(lastErrorLoc); return true } return false } },
        // Chord (Alt+K puis C/U) : commenter / dé-commenter les lignes sélectionnées.
        // Deux variantes : Alt relâché avant la 2e touche, OU Alt maintenu (Alt+K Alt+C).
        { key: 'Alt-k c', run: (v) => toggleLineComment(v, true) },
        { key: 'Alt-k u', run: (v) => toggleLineComment(v, false) },
        { key: 'Alt-k Alt-c', run: (v) => toggleLineComment(v, true) },
        { key: 'Alt-k Alt-u', run: (v) => toggleLineComment(v, false) },
      ]),
      keymap.of(searchKeymap),   // Ctrl+F (rechercher), Ctrl+G (suivant), etc.
      indentUnit.of('    '),
      // Auto-paires natives : «(» insère «()», entoure la sélection si elle
      // existe, et Backspace supprime la paire vide (closeBracketsKeymap).
      closeBrackets(),
      autocompletion({ override: [ollinComplete], activateOnTyping: true }),
      EditorView.updateListener.of(update => {
        if (!update.docChanged || loadingFile) return
        if (isRunning) clearAndStop()   // script modifié → la prévisualisation en cours est obsolète
        clearTimeout(saveTimer)
        saveTimer = setTimeout(scheduleSave, 500)
        // Mode Auto : chaque modif réarme un compte à rebours ; 2 s d'inactivité → relance.
        const chk = document.getElementById('autoexec-chk')
        if (chk && chk.checked) {
          clearTimeout(autoexecTimer)
          autoexecTimer = setTimeout(() => relaunch(), 2000)
        }
      }),
]

// Raccourcis affichés par la popup d'aide (F1 / bouton « Aide »).
// ⚠ SOURCE UNIQUE : à garder synchronisé avec les keymaps ci-dessus (editKeymap,
// le keymap.of([...]) Alt-Enter/F4/Alt-k…, searchKeymap, foldKeymap, historyKeymap)
// et le raccourci d'exécution géré dans onGlobalKeydown.
const SHORTCUTS = [
  { cat: 'Exécution', items: [
    { keys: ['Alt', '↵'],   desc: 'Exécuter / relancer le script' },
    { keys: ['Échap'],      desc: 'Arrêter l’exécution en cours' },
    { keys: ['F4'],         desc: 'Aller à la première erreur' },
  ]},
  { cat: 'Édition', items: [
    { keys: ['Tab'],            desc: 'Indenter au curseur (ou accepter la complétion si la popup est ouverte)' },
    { keys: ['Maj', 'Tab'],     desc: 'Désindenter' },
    { keys: ['Ctrl', 'Espace'], desc: 'Déclencher l’autocomplétion' },
    { keys: ['Alt+K', 'C'], sep: ' puis ', desc: 'Commenter les lignes sélectionnées' },
    { keys: ['Alt+K', 'U'], sep: ' puis ', desc: 'Décommenter les lignes sélectionnées' },
    { keys: ['Alt', 'Maj', 'F'],desc: 'Reformater le code (indentation)' },
    { keys: ['Ctrl', 'Z'],      desc: 'Annuler' },
    { keys: ['Ctrl', 'Y'],      desc: 'Rétablir (ou Ctrl+Maj+Z)' },
  ]},
  { cat: 'Recherche', items: [
    { keys: ['Ctrl', 'F'],      desc: 'Rechercher dans le fichier' },
    { keys: ['Ctrl', 'G'],      desc: 'Occurrence suivante' },
    { keys: ['Maj', 'Ctrl', 'G'], desc: 'Occurrence précédente' },
  ]},
  { cat: 'Pliage', items: [
    { keys: ['Ctrl', 'Maj', '['], desc: 'Plier le bloc' },
    { keys: ['Ctrl', 'Maj', ']'], desc: 'Déplier le bloc' },
  ]},
  { cat: 'Aide', items: [
    { keys: ['F1'], desc: 'Afficher / masquer cette aide' },
  ]},
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
// Parade : un écouteur enregistré ICI en phase capture. Tant que le runtime a été
// armé (un programme graphique a tourné) et que l'éditeur a le focus, on exécute
// Backspace/Tab via les VRAIES commandes CodeMirror (le même `editKeymap` que
// l'éditeur → deleteCharBackward, deleteGroupBackward, indentMore/Less,
// acceptCompletion…), puis on stoppe l'événement pour que GLFW ne le voie pas. On
// ne touche QU'À ces deux touches : toutes les autres passent normalement à
// CodeMirror (GLFW ne les bloque pas), donc aucune régression d'édition.
//
// Le drapeau « armé » vit au niveau PAGE (window), pas au niveau vue : l'écouteur
// GLFW est global et n'est JAMAIS retiré au changement de vue (runtime WASM
// partagé, aucun CloseWindow). Un drapeau par-vue repartirait à false à chaque
// remontage → après un run puis un aller-retour de vue, GLFW mangerait encore
// Backspace/Tab alors que la parade serait éteinte (bug intermittent).
const isRuntimeArmed = () => !!window.__ollinGfxKbdArmed
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
    // Sémantique CM : avec Maj on n'exécute QUE b.shift (jamais b.run), sinon un
    // binding sans variante Maj (ex. softTab) se déclencherait à tort sur Maj+Tab.
    const cmd = e.shiftKey ? b.shift : b.run
    if (cmd && cmd(view)) return true
  }
  return false
}
const onGlobalKeydown = e => {
  // F1 : bascule la popup d'aide (raccourcis). En capture → marche quel que soit
  // le focus ; preventDefault pour couper l'aide native du navigateur.
  if (e.key === 'F1') {
    e.preventDefault()
    e.stopImmediatePropagation()
    toggleHelp()
    return
  }
  // Échap ferme d'abord l'aide si elle est ouverte (avant d'arrêter un run).
  if (e.key === 'Escape' && helpOpen()) {
    e.preventDefault()
    e.stopImmediatePropagation()
    closeHelp()
    return
  }
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
  if (!isRuntimeArmed() || !view.hasFocus) return
  if (e.key !== 'Backspace' && e.key !== 'Tab') return   // seules touches mangées par GLFW
  if (runEditKeymap(e)) {
    e.preventDefault()
    e.stopImmediatePropagation()
  }
}
window.addEventListener('keydown', onGlobalKeydown, true)   // capture + avant l'écouteur GLFW
disposers.push(() => window.removeEventListener('keydown', onGlobalKeydown, true))

// L'écouteur clavier GLFW est global (window) : sans garde, taper/naviguer dans
// l'éditeur piloterait aussi un programme graphique en cours (ex. le sample voxel).
// On signale au moteur (keyboard_module) d'ignorer le clavier tant que l'ÉDITEUR a
// le focus ; dès qu'il le perd (canvas/bouton), le jeu reçoit de nouveau les touches.
const onEditorFocus = () => { window.__ollinKbdBlocked = true }
const onEditorBlur  = () => { window.__ollinKbdBlocked = false }
view.contentDOM.addEventListener('focus', onEditorFocus)
view.contentDOM.addEventListener('blur', onEditorBlur)
window.__ollinKbdBlocked = (document.activeElement === view.contentDOM)
disposers.push(() => {
  view.contentDOM.removeEventListener('focus', onEditorFocus)
  view.contentDOM.removeEventListener('blur', onEditorBlur)
  window.__ollinKbdBlocked = false   // quitte la vue → ne pas bloquer le run autonome
})

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
    const move = key.getAttribute('data-move')
    if (move) {
      const forward = move === '1'
      const sel = view.state.selection.main
      // Sélection : on la replie sur le bord visé (comme les flèches) ; curseur : ±1 caractère.
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

// Mode exemple : le projet courant est TRANSITOIRE (chargé depuis le dépôt, jamais
// persisté). On voit/navigue tous ses fichiers, mais aucune écriture en base ni
// mutation de structure (créer/renommer/supprimer) — « Créer un projet » pour éditer.
const isExample = () => !!(currentProject && currentProject.example)

const fileKey = id => 'ollin-pg-file:' + id           // dernier fichier ouvert / projet
const scripts = p => Object.keys(p.files).filter(f => f !== Store.MANIFEST).sort()

// Affiche/masque les boutons de MUTATION de structure (＋ fichier / ＋ ressource) :
// masqués en mode exemple (projet transitoire non éditable), visibles sinon.
function setStructuralUI(enabled) {
  newFileBtn.style.display = enabled ? '' : 'none'
  newResBtn.style.display  = enabled ? '' : 'none'
}

function setEditorText(text) {
  if (isRunning) clearAndStop()   // charger un autre script ferme la prévisualisation obsolète
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
  if (!currentProject || isExample()) return   // un exemple ne se persiste jamais
  flushEditorToFile()
  updateSyncBadge()   // une frappe non poussée → pastille bleue (local plus récent)
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

    if (!isExample()) {   // exemple : lecture/navigation seule, pas de mutation
      const acts = document.createElement('span')
      acts.className = 'file-acts'
      acts.appendChild(iconBtn(isEntry ? '★' : '☆', isEntry ? 'Point d\'entrée' : 'Définir comme point d\'entrée',
        e => { e.stopPropagation(); setEntry(path) }))
      acts.appendChild(iconBtn('✎', 'Renommer', e => { e.stopPropagation(); renameFile(path) }))
      acts.appendChild(iconBtn('🗑', 'Supprimer', e => { e.stopPropagation(); deleteFile(path) }))
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
  if (path === currentFile) return
  flushEditorToFile()
  currentFile = path
  setEditorText(currentProject.files[path] ?? '')
  if (!isExample()) localStorage.setItem(fileKey(currentProject.id), path)
  renderFiles()
  view.focus()
}

async function newFile() {
  if (!currentProject || isExample()) return   // aucun projet éditable (ex. exemple 404)
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
    if (!isExample()) {
      const acts = document.createElement('span'); acts.className = 'file-acts'
      acts.appendChild(iconBtn('✎', 'Renommer', e => { e.stopPropagation(); renameResource(name) }))
      acts.appendChild(iconBtn('🗑', 'Supprimer', e => { e.stopPropagation(); deleteResource(name) }))
      row.appendChild(acts)
    }
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
  setStructuralUI(true)   // projet réel → mutations autorisées
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
  // Pastille de synchro : checkRemoteFreshness la (ré)initialise dès son entrée
  // (état local immédiat, puis verdict distant après le contrôle réseau).
  checkRemoteFreshness(p)   // garde-fou d'ouverture (non bloquant)
}

async function switchProject(id) {
  if (currentProject && !isExample()) {       // un exemple (transitoire) n'a rien à sauver
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
  projectMenu.appendChild(menuItem('✨ Nouveau projet vide', false, async () => {
    const name = await askFreeProjectName('Sans titre'); if (!name) return
    const p = await Store.createProject(name)
    closeMenu()
    await autoPushNewProject(p)   // dépôt paramétré → créé sur GitHub
    await openProject(p.id)
  }))
  projectMenu.appendChild(menuItem('📂 Ouvrir un projet', true, renderMenuOpen))
  projectMenu.appendChild(menuItem('📥 Ouvrir depuis GitHub', true, () => (GH.isConnected() ? renderMenuRemote() : renderMenuConnect())))
  projectMenu.appendChild(menuItem('📄 Ouvrir un exemple', true, renderMenuExamples))
  // Actions sur le PROJET COURANT : masquées en mode exemple (projet transitoire,
  // rien à renommer/dupliquer/supprimer en base).
  if (currentProject && !isExample()) {
    projectMenu.appendChild(menuSep())
    projectMenu.appendChild(menuItem('✎ Renommer', false, async () => {
      const name = await askFreeProjectName(currentProject.name, {
        label: 'Nouveau nom :',
        exclude: { id: currentProject.id, slug: (currentProject.remote && currentProject.remote.slug) || currentProject.id },
      })
      if (!name) return
      flushEditorToFile(); await Store.saveProject(currentProject)
      const p = await Store.renameProject(currentProject.id, name)
      closeMenu(); await loadProject(p.id)
    }))
    projectMenu.appendChild(menuItem('⧉ Dupliquer', false, async () => {
      flushEditorToFile(); await Store.saveProject(currentProject)
      const dupName = await askFreeProjectName(currentProject.name + ' (copie)'); if (!dupName) return
      const copy = await Store.createProject(dupName)
      copy.files = { ...currentProject.files }; copy.entry = currentProject.entry
      copy.resources = { ...currentProject.resources }   // dupliquer AUSSI les assets
      delete copy.files[Store.MANIFEST]
      await Store.saveProject(copy)
      closeMenu()
      await autoPushNewProject(copy)   // dépôt paramétré → créé sur GitHub
      await switchProject(copy.id)
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

  projectMenu.appendChild(menuSep())
  const ghLabel = GH.isConnected() ? ('🐙 GitHub' + (ghLogin ? ' : @' + ghLogin : '')) : '🐙 GitHub'
  projectMenu.appendChild(menuItem(ghLabel, true, renderMenuGithub))
  projectMenu.appendChild(menuSep())
  projectMenu.appendChild(menuItem('⌨ Raccourcis clavier (F1)', false, () => { closeMenu(); openHelp() }))
}

// Sous-menu GitHub : regroupe toutes les fonctionnalités (connexion, dépôt,
// pousser/récupérer, ouvrir, déconnexion). Accédé depuis « 🐙 GitHub » à la racine.
function renderMenuGithub() {
  projectMenu.innerHTML = ''
  if (!GH.isConnected()) {
    projectMenu.appendChild(menuHeader('GitHub', renderMenuRoot))
    projectMenu.appendChild(menuItem('🔗 Se connecter à GitHub', true, renderMenuConnect))
    return
  }
  const hdr = menuHeader('GitHub' + (ghLogin ? ' : @' + ghLogin : ''), renderMenuRoot)
  projectMenu.appendChild(hdr)
  if (!ghLogin) {
    const span = hdr.querySelector('span')
    GH.getUser().then(u => { ghLogin = u.login; if (span) span.textContent = 'GitHub : @' + u.login }).catch(() => {})
  }
  projectMenu.appendChild(menuItem('🗄 Dépôt : ' + GH.getRepo(), false, () => {
    const v = prompt('Dépôt cible (nom, ou « owner/repo » pour un dépôt partagé) :', GH.getRepo())
    if (v === null) return
    GH.setRepo(v)
    renderMenuGithub()
  }))
  if (currentProject && !isExample()) {   // pousser/récupérer agit sur un projet réel
    projectMenu.appendChild(menuItem('⬆ Pousser vers GitHub', false, () => ghPush()))
    projectMenu.appendChild(menuItem('⬇ Récupérer (Pull)', false, ghPull))
  }
  projectMenu.appendChild(menuItem('⏻ Déconnexion', false, () => { GH.clearToken(); ghLogin = null; renderMenuGithub() }))
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
  projectMenu.appendChild(menuHeader('Se connecter à GitHub', renderMenuGithub))
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

// Si GitHub est connecté (dépôt paramétré), tout NOUVEAU projet est aussitôt créé
// sur le dépôt. Best-effort : en cas d'échec (réseau/permissions/conflit de slug),
// le projet reste en local et un message le signale — « Pousser vers GitHub » reste
// disponible pour réessayer.
async function autoPushNewProject(p) {
  if (!GH.isConnected()) return
  setStatus('Création sur GitHub…')
  try {
    await GH.ensureRepo()
    await GH.pushProject(p, null, {})
    p.remote.localSha = localContentSha(p)   // base locale = ce qui vient d'être poussé
    await Store.saveProject(p)   // persiste project.remote (slug, folderSha, localSha)
    setStatus('Projet créé sur GitHub ✓', true)
  } catch (e) {
    setStatus('Créé en local — GitHub : ' + (e && e.message ? e.message : e), true, true)
  }
}

async function ghPush(force) {
  closeMenu()
  if (!currentProject) return
  flushEditorToFile(); await Store.saveProject(currentProject)
  setStatus('Envoi vers GitHub…')
  try {
    await GH.ensureRepo()
    await GH.pushProject(currentProject, null, { force })
    currentProject.remote.localSha = localContentSha(currentProject)   // base locale = poussée
    await Store.saveProject(currentProject)   // persister project.remote (folderSha, localSha)
    syncRemoteAhead = false
    updateSyncBadge()   // à jour → pastille verte
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
    p.remote.localSha = localContentSha(p)   // base locale = ce qui vient d'être récupéré
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

// ── Pastille d'état de synchro GitHub (tri-état) ────────────────────────────
// jaune = distant plus récent (Pull) · bleu = local plus récent (Push) · vert = à jour.
// `syncRemoteAhead` = dernier verdict RÉSEAU (le distant a-t-il bougé depuis notre
// dernière synchro ?) ; l'avance LOCALE se déduit sans réseau en comparant le hash
// du contenu courant à `remote.localSha` (posé à chaque push/pull).
let syncRemoteAhead = false

// Hash 53 bits déterministe (cyrb53) — comparaison de contenu, pas de crypto.
function hashStr(str) {
  let h1 = 0xdeadbeef, h2 = 0x41c6ce57
  for (let i = 0; i < str.length; i++) {
    const c = str.charCodeAt(i)
    h1 = Math.imul(h1 ^ c, 2654435761)
    h2 = Math.imul(h2 ^ c, 1597334677)
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909)
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909)
  return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(16)
}

// Empreinte du contenu local d'un projet : entry + name + fichiers (hors MANIFEST,
// régénéré à chaque save → instable) + ressources. Identique après un push et après
// un pull du même contenu → base fiable pour « le local a-t-il changé depuis ? ».
// Les ressources (base64, potentiellement plusieurs Mo) ne sont re-hashées que si leur
// signature (clés + tailles) change → l'appel par frappe (scheduleSave) ne re-hashe que
// les fichiers .ol, pas les gros assets qui ne bougent pas quand on édite du code.
let _resHashCache = { sig: '', hash: '' }
function localContentSha(project) {
  const parts = ['entry:' + (project.entry || ''), 'name:' + (project.name || '')]
  const files = project.files || {}
  for (const k of Object.keys(files).sort()) {
    if (k === Store.MANIFEST) continue
    parts.push('F:' + k + '|' + files[k])
  }
  const res = project.resources || {}
  const keys = Object.keys(res).sort()
  let sig = ''
  for (const k of keys) sig += k + ':' + (res[k].b64 || '').length + ';'
  if (sig !== _resHashCache.sig) {   // ressources modifiées (ajout/retrait/remplacement) → re-hash
    const rparts = []
    for (const k of keys) rparts.push('R:' + k + '|' + (res[k].b64 || ''))
    _resHashCache = { sig, hash: hashStr(rparts.join('\n')) }
  }
  return hashStr(parts.join('\n') + '|R#' + _resHashCache.hash)
}

function setSyncDot(state) {
  projectBtn.classList.toggle('sync-remote', state === 'remote')
  projectBtn.classList.toggle('sync-local',  state === 'local')
  projectBtn.classList.toggle('sync-ok',     state === 'ok')
}

// Rafraîchit la pastille depuis l'état courant (sans réseau) : distant en avance →
// jaune ; sinon local modifié → bleu ; sinon à jour → vert. Aucune pastille si le
// projet n'est pas lié à GitHub (ou déconnecté, ou exemple).
function updateSyncBadge() {
  const p = currentProject
  if (!p || isExample() || !p.remote || !p.remote.slug || !GH.isConnected()) {
    setSyncDot(null)
    return
  }
  if (syncRemoteAhead) {
    setSyncDot('remote')
    return
  }
  // base absente (jamais synchronisé avec cette version, ou hors ligne au dernier open) →
  // on ne peut pas affirmer « à jour » : traiter comme local en avance (inciter à pousser).
  const base = p.remote.localSha
  const localChanged = base == null || localContentSha(p) !== base
  setSyncDot(localChanged ? 'local' : 'ok')
}

// Garde-fou d'ouverture : vérifie en arrière-plan si le distant a bougé, met à jour
// la pastille et (si distant plus récent) affiche un rappel Pull. PASSIF : aucun Pull
// automatique. Backfille `remote.localSha` pour les projets synchronisés avant cette
// fonctionnalité (base absente + distant à jour → le local EST la base).
async function checkRemoteFreshness(project) {
  syncRemoteAhead = false
  updateSyncBadge()   // affiche déjà vert/bleu selon le local en attendant le réseau
  if (!project.remote || !project.remote.slug || !GH.isConnected()) return
  try {
    const cur = await GH.remoteFolderSha(project.remote.slug)
    if (!currentProject || currentProject.id !== project.id) return   // projet changé entre-temps
    const known = project.remote.folderSha || null
    syncRemoteAhead = known !== null && GH.folderMoved(cur, known)
    if (!syncRemoteAhead && known !== null && project.remote.localSha == null) {
      project.remote.localSha = localContentSha(project)   // backfill de la base locale
      Store.saveProject(project).catch(() => {})
    }
    updateSyncBadge()
    if (syncRemoteAhead) setStatus('⬇ Version plus récente sur GitHub — « Récupérer (Pull) » pour l\'obtenir')
  } catch (_) { /* hors-ligne / token invalide : on garde l'état local */ }
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
        p.remote.localSha = localContentSha(p)   // base locale = ce qui vient d'être récupéré
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
  txt.innerHTML = '📄 Exemple <b style="color:#c9d1e0">' + file + '</b> — non enregistré (un rafraîchissement recharge l\'exemple)'
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
  // fraîche. collectSampleProject rejette sur 404 du fichier d'entrée.
  let bundle
  try {
    bundle = await Run.collectSampleProject(file, ctx.v)
  } catch (e) {
    removeExampleBanner()
    setStructuralUI(true)
    setEditorText('## ' + (e && e.message ? e.message : 'exemple introuvable : ' + file))
    setStatus('Exemple introuvable : ' + file, true, true)
    return
  }
  // Projet TRANSITOIRE : entrée + imports + assets, visibles et navigables, mais non
  // persistés (marqueur `example`). Un refresh recharge la version du dépôt.
  currentProject = {
    id: '__exemple__', name: file, entry: bundle.entry,
    files: bundle.files, resources: bundle.resources, example: true,
  }
  currentFile = bundle.entry
  setEditorText(currentProject.files[bundle.entry] ?? '')
  setStructuralUI(false)         // pas de création/renommage/suppression sur un exemple
  renderFiles()
  renderResources()
  showExampleBanner(file)
  projectLabel.textContent = file
  // Le rail reste FERMÉ par défaut (comme pour un projet) — le bouton latéral l'ouvre.
}

// Ensemble des noms de projets DÉJÀ PRIS (en minuscules), local + distant GitHub si
// connecté. `exclude` = { id, slug } à ignorer (le projet lui-même lors d'un renommage).
// Récupéré une seule fois → la boucle de saisie ne re-télécharge pas à chaque essai.
async function takenProjectNames(exclude = {}) {
  const names = new Set()
  let remoteFailed = false
  for (const p of await Store.listProjects()) {
    if (p.id === exclude.id) continue
    names.add((p.name || '').trim().toLowerCase())
  }
  if (GH.isConnected()) {
    try {
      for (const r of await GH.listRemoteProjects()) {
        if (r.slug === exclude.slug) continue
        names.add((r.name || '').trim().toLowerCase())
      }
    } catch (_) { remoteFailed = true }   // distant injoignable → signalé à l'appelant
  }
  names.delete('')
  return { names, remoteFailed }
}

// Demande un nom de projet LIBRE (ni en local ni sur le dépôt distant) : reboucle
// tant que le nom est vide ou déjà pris. Renvoie le nom validé, ou null si annulé.
// `opts` : { label, exclude:{id,slug} } (exclusion = le projet lui-même en renommage).
async function askFreeProjectName(defName, opts = {}) {
  const label = opts.label || 'Nom du projet :'
  if (GH.isConnected()) setStatus('Vérification des noms…')
  const { names, remoteFailed } = await takenProjectNames(opts.exclude)
  // Nettoie le « Vérification… » : avertissement transitoire si le distant a échoué,
  // sinon efface (sinon le message resterait affiché après annulation/renommage).
  if (remoteFailed) setStatus('Noms distants non vérifiés (dépôt injoignable)', true, true)
  else if (GH.isConnected()) setStatus('')
  let name = prompt(label, defName)
  while (name !== null) {
    const clean = name.trim()
    if (!clean) {
      name = prompt('Le nom ne peut pas être vide. ' + label, defName)
    } else if (names.has(clean.toLowerCase())) {
      name = prompt(`Un projet « ${clean} » existe déjà (local ou GitHub). Choisis un autre nom :`, clean)
    } else {
      return clean
    }
  }
  return null
}

// Fork explicite : convertit l'exemple affiché en projet éditable persistant, en
// copiant TOUS ses fichiers (entrée + imports) et ses ressources (assets), pas
// seulement le fichier ouvert.
async function forkExampleToProject(file) {
  flushEditorToFile()   // capter les frappes non enregistrées du fichier courant
  const name = await askFreeProjectName(file.replace(/\.ol$/, ''))
  if (!name) return
  const p = await Store.createProject(name)
  if (isExample()) {
    p.files     = { ...currentProject.files }
    p.resources = { ...currentProject.resources }
    p.entry     = currentProject.entry
    delete p.files[Store.MANIFEST]   // régénéré par saveProject
  } else {
    p.files[p.entry] = view.state.doc.toString()
  }
  await Store.saveProject(p)
  await autoPushNewProject(p)   // dépôt paramétré → créé sur GitHub
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
    runBtn.innerHTML = ICON_RUN + '<span class="btn-label"> Exécuter</span><kbd>Alt+↵</kbd>'
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
  lastErrorLoc = null   // sortie vidée → plus de cible F4 périmée
  outputPane.style.overflow = ''
  setRunning(false)
  setOutputVisible(false)   // retour éditeur plein écran
}

// Localisation de la dernière erreur affichée (null si la sortie n'est pas une
// erreur) → cible du raccourci F4 « aller à la première erreur ».
let lastErrorLoc = null

function showOutput(text) {
  canvasEl.style.display = 'none'
  outputEl.style.display = 'block'
  if (outputHdr) outputHdr.style.display = 'flex'
  outputPane.style.overflow = ''
  if (!text) {
    outputEl.textContent = '(aucune sortie)'
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
  lastErrorLoc = loc
  if (!loc) { outputEl.textContent = text; return }
  outputEl.textContent = ''
  outputEl.appendChild(document.createTextNode(text.slice(0, loc.index)))
  const link = document.createElement('span')
  link.className = 'err-link'
  link.textContent = loc.str
  link.title = 'Aller à la ligne fautive (F4)'
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
  clearTimeout(autoexecTimer)   // tout lancement (bouton, Alt+Entrée, auto) vaut relance → annule celle en attente
  try { ollin.pauseMainLoop() } catch(_) {}
  setRunning(false)
  outputEl.className = ''
  lastErrorLoc = null   // nouvelle exécution : F4 ne doit plus viser l'erreur précédente
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
      setRunning(true)   // le drapeau __ollinGfxKbdArmed est posé par runProgram (pg-run.js)
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

// ── Mode Auto (relance différée) — navigateur desktop uniquement (souris) ──────
// Révélé seulement sur pointeur fin : caché sur tactile/mobile pour l'instant.
const autoexecWrap = document.getElementById('autoexec-wrap')
const autoexecChk  = document.getElementById('autoexec-chk')
if (autoexecWrap && window.matchMedia && window.matchMedia('(pointer: fine)').matches) {
  autoexecWrap.style.display = ''
  const onAutoexec = () => {
    autoexecWrap.classList.toggle('on', autoexecChk.checked)
    if (!autoexecChk.checked) {
      clearTimeout(autoexecTimer)   // décoché → annule une relance en attente
      return
    }
    if (!isRunning) relaunch()      // coché → lance tout de suite si le script ne tourne pas déjà
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

// ── Mode plein écran (vue #/run, MÊME fenêtre) ──────────────────────────────
// Bascule vers la vue #/run DANS la fenêtre courante (pas de nouvel onglet : un
// nouvel onglet crée un contexte GLFW distinct dont l'écouteur clavier casse
// Backspace/Tab au retour éditeur). Le projet actif est commité dans IndexedDB
// avant la bascule — la vue #/run le recharge depuis là.
const standaloneBtn = document.getElementById('standalone-btn')
standaloneBtn.addEventListener('click', async () => {
  if (exampleFile) {
    // Mode exemple : exécute le MÊME exemple frais en autonome (pas de projet).
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

// ── Popup d'aide (raccourcis) ────────────────────────────────────────────────
// Rendue une fois depuis SHORTCUTS ; ouverte par le bouton « Aide » ou F1.
const helpOverlay = document.getElementById('help-overlay')
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
function renderHelp() {
  const body = document.getElementById('help-body')
  if (!body) return
  body.innerHTML = SHORTCUTS.map(group => {
    const rows = group.items.map(it => {
      const keys = it.keys.map(k => '<kbd>' + esc(k) + '</kbd>')
        .join(it.sep ? '<span class="plus">' + esc(it.sep) + '</span>' : '<span class="plus">+</span>')
      return '<div class="help-row"><span class="help-desc">' + esc(it.desc) + '</span><span class="help-keys">' + keys + '</span></div>'
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
  if (!files.length || !currentProject || isExample()) return
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
  // NB : on ne remet PAS __ollinGfxKbdArmed à false — l'écouteur GLFW reste posé
  // sur window après le démontage, la parade doit donc rester armée page-wide.
  clearTimeout(autoexecTimer)   // pas de relance fantôme après le démontage de la vue
  try { view.destroy() } catch (_) {}
  if (window.__ollinView === view) window.__ollinView = undefined
})

return () => { for (const d of disposers) d() }
}
