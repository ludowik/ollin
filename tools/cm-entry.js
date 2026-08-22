// The entry point of the CodeMirror bundle served locally (docs/vendor/codemirror.js).
// Packed by esbuild (see the "build:cm" script and the build-playground.yml workflow), so
// the playground no longer depends on the esm.sh CDN.
// It re-exports only the symbols docs/playground.html uses.
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
