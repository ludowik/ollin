// Réglages d'affichage partagés des blocs de code CodeMirror.
// Source unique, utilisée par le playground (docs/playground.html) ET le
// tutoriel (docs/index.html) : à spreader dans leur EditorView.theme respectif.
// Ne contient que la géométrie d'affichage (padding, interligne, gouttières) ;
// chaque page garde ses spécificités (taille de police, bordures, etc.).
export const CODE_DISPLAY = {
  '.cm-line': { padding: '0 9px 4px', lineHeight: '1.12' },
  '.cm-lineNumbers .cm-gutterElement': { padding: '0 4px', minWidth: '1.8em', fontSize: '11.5px', userSelect: 'none' },
  '.cm-foldGutter .cm-gutterElement': { padding: '0', color: '#566089', cursor: 'pointer' },
  '.cm-foldGutter .cm-gutterElement:hover': { color: '#7c83ff' },
  '.cm-foldPlaceholder': { background: '#242742', border: '1px solid #2e3150', color: '#7c85a2', borderRadius: '4px', padding: '0 6px', margin: '0 2px' },
}
