// Point d'entrée du bundle CodeMirror servi localement (docs/vendor/codemirror.js).
// Empaqueté par esbuild (cf. script "build:cm" + workflow build-playground.yml) →
// le playground n'a plus de dépendance au CDN esm.sh.
// Ré-exporte uniquement les symboles utilisés par docs/playground.html.
export { EditorState } from '@codemirror/state'
export {
  EditorView, lineNumbers, keymap, drawSelection,
  highlightActiveLine, highlightActiveLineGutter,
} from '@codemirror/view'
export { defaultKeymap, historyKeymap, history, indentWithTab } from '@codemirror/commands'
export {
  StreamLanguage, syntaxHighlighting, HighlightStyle, indentUnit,
  codeFolding, foldGutter, foldKeymap, foldService,
} from '@codemirror/language'
export { tags } from '@lezer/highlight'
export {
  autocompletion, completionKeymap, acceptCompletion,
  closeBrackets, closeBracketsKeymap,
} from '@codemirror/autocomplete'
export {
  search, searchKeymap, highlightSelectionMatches, openSearchPanel,
} from '@codemirror/search'
