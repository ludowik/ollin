// CodeMirror settings shared by the tutorial (views/tutorial.js) AND the playground
// (views/playground.js). Single source, spread into their respective EditorView.theme. Each
// view keeps its own specifics (background, borders, font size, autocomplete styles).

// Display geometry (padding, line spacing, fold gutters).
export const CODE_DISPLAY = {
  '.cm-line': { padding: '0 9px 4px', lineHeight: '1.12' },
  '.cm-lineNumbers .cm-gutterElement': { padding: '0 4px', minWidth: '1.8em', fontSize: '11.5px', userSelect: 'none' },
  '.cm-foldGutter .cm-gutterElement': { padding: '0', color: '#566089', cursor: 'pointer' },
  '.cm-foldGutter .cm-gutterElement:hover': { color: '#9ba1ff' },
  '.cm-foldPlaceholder': { background: '#242742', border: '1px solid #3a3f63', color: '#a3adc4', borderRadius: '4px', padding: '0 6px', margin: '0 2px' },
}

// Theme rules STRICTLY identical between the two views (active line, focused cursor,
// selection). Extracted so they are no longer copied twice: a change of selection or caret
// tint now happens here only.
export const CODE_THEME_BASE = {
  '.cm-activeLine': { background: 'rgba(255,255,255,0.03)' },
  '.cm-activeLineGutter': { background: 'rgba(255,255,255,0.03)', color: '#a3adc4' },
  '&.cm-focused .cm-cursor': { borderLeftColor: '#9ba1ff', borderLeftWidth: '2px' },
  '.cm-selectionBackground': { background: 'rgba(255,255,255,0.18) !important' },
  '&.cm-focused .cm-selectionBackground': { background: 'rgba(255,255,255,0.25) !important' },
}

// Shared SVG icons (the Run, Copy and done buttons). Single source.
export const ICONS = {
  run:  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="12" height="12" fill="currentColor" aria-hidden="true"><path d="M3 2l11 6-11 6V2z"/></svg>',
  copy: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><rect x="5.5" y="5.5" width="9" height="9" rx="1.5"/><path d="M10.5 5.5V3a1 1 0 00-1-1H3a1 1 0 00-1 1v7a1 1 0 001 1h2.5"/></svg>',
  ok:   '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M3 8l4 4 6-6"/></svg>',
}
