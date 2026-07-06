// Réglages CodeMirror partagés par le tutoriel (views/tutoriel.js) ET le
// playground (views/playground.js). Source unique : à spreader dans leur
// EditorView.theme respectif. Chaque vue garde ses spécificités (fond, bordures,
// taille de police, styles d'autocomplétion).

// Géométrie d'affichage (padding, interligne des lignes, gouttières de pliage).
export const CODE_DISPLAY = {
  '.cm-line': { padding: '0 9px 4px', lineHeight: '1.12' },
  '.cm-lineNumbers .cm-gutterElement': { padding: '0 4px', minWidth: '1.8em', fontSize: '11.5px', userSelect: 'none' },
  '.cm-foldGutter .cm-gutterElement': { padding: '0', color: '#566089', cursor: 'pointer' },
  '.cm-foldGutter .cm-gutterElement:hover': { color: '#7c83ff' },
  '.cm-foldPlaceholder': { background: '#242742', border: '1px solid #2e3150', color: '#7c85a2', borderRadius: '4px', padding: '0 6px', margin: '0 2px' },
}

// Règles de thème STRICTEMENT identiques entre les deux vues (ligne active,
// curseur au focus, sélection). Extraites pour ne plus être copiées deux fois
// (un changement de teinte de sélection/caret ne se fait plus qu'ici).
export const CODE_THEME_BASE = {
  '.cm-activeLine': { background: 'rgba(255,255,255,0.03)' },
  '.cm-activeLineGutter': { background: 'rgba(255,255,255,0.03)', color: '#7c85a2' },
  '&.cm-focused .cm-cursor': { borderLeftColor: '#7c83ff', borderLeftWidth: '2px' },
  '.cm-selectionBackground': { background: 'rgba(255,255,255,0.18) !important' },
  '&.cm-focused .cm-selectionBackground': { background: 'rgba(255,255,255,0.25) !important' },
}

// Icônes SVG partagées (boutons Exécuter / Copier / validé). Source unique.
export const ICONS = {
  run:  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="12" height="12" fill="currentColor" aria-hidden="true"><path d="M3 2l11 6-11 6V2z"/></svg>',
  copy: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><rect x="5.5" y="5.5" width="9" height="9" rx="1.5"/><path d="M10.5 5.5V3a1 1 0 00-1-1H3a1 1 0 00-1 1v7a1 1 0 001 1h2.5"/></svg>',
  ok:   '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M3 8l4 4 6-6"/></svg>',
}
