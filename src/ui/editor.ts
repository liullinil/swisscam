import * as monaco from 'monaco-editor'
import editorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker'
import type { Diag } from '../core/types.ts'

declare global {
  // eslint-disable-next-line no-var
  var MonacoEnvironment: monaco.Environment | undefined
}

self.MonacoEnvironment = {
  getWorker: () => new editorWorker(),
}

const LANG = 'gcode'

function registerLanguage() {
  if (monaco.languages.getLanguages().some((l) => l.id === LANG)) return

  monaco.languages.register({ id: LANG })

  monaco.languages.setMonarchTokensProvider(LANG, {
    ignoreCase: true,
    tokenizer: {
      root: [
        [/\(.*?\)/, 'comment'],
        [/\(.*$/, 'comment'],
        [/;.*$/, 'comment'],
        [/^\s*\$\d+\s*$/, 'channel'],
        [/![0-9]*(?:L[0-9]+)?/, 'sync'],
        [/^\s*\//, 'skip'],
        [/^\s*%/, 'skip'],
        [/\b(IF|WHILE|GOTO|DO|END|THEN|EQ|NE|GT|LT|GE|LE|AND|OR)\b/i, 'keyword'],
        [/#\d+/, 'variable'],
        [/[NO][-+]?\d+/, 'label'],
        [/[Gg][-+]?\d+(?:\.\d+)?/, 'gcode'],
        [/[Mm][-+]?\d+/, 'mcode'],
        [/[TtDd][-+]?\d+/, 'tool'],
        [/[FfSs][-+]?[\d.]+/, 'feed'],
        [/[XYZUVWABCIJKRPQHL][-+]?[\d.]*/i, 'axis'],
        [/[[\]]/, 'delimiter'],
      ],
    },
  } as monaco.languages.IMonarchLanguage)

  monaco.editor.defineTheme('swisscam', {
    base: 'vs-dark',
    inherit: true,
    colors: {
      'editor.background': '#14171c',
      'editorLineNumber.foreground': '#4a5262',
      'editor.lineHighlightBackground': '#1b1f26',
    },
    rules: [
      { token: 'comment', foreground: '6b7484', fontStyle: 'italic' },
      { token: 'channel', foreground: 'f0a020', fontStyle: 'bold' },
      { token: 'sync', foreground: 'ff8ad8', fontStyle: 'bold' },
      { token: 'gcode', foreground: '4ea3ff' },
      { token: 'mcode', foreground: '37d39a' },
      { token: 'tool', foreground: 'ffc857' },
      { token: 'feed', foreground: 'c47bff' },
      { token: 'axis', foreground: 'dfe4ec' },
      { token: 'label', foreground: '8d97a8' },
      { token: 'variable', foreground: 'ff9d5c' },
      { token: 'keyword', foreground: 'ff6b6b' },
      { token: 'skip', foreground: '4a5262' },
    ],
  })
}

export interface EditorHandle {
  editor: monaco.editor.IStandaloneCodeEditor
  setDiags(diags: Diag[]): void
  highlight(line: number | null): void
  goTo(line: number): void
}

export function createEditor(host: HTMLElement, initial: string, onChange: (text: string) => void): EditorHandle {
  registerLanguage()
  const editor = monaco.editor.create(host, {
    value: initial,
    language: LANG,
    theme: 'swisscam',
    automaticLayout: true,
    minimap: { enabled: false },
    fontSize: 13,
    lineNumbersMinChars: 4,
    scrollBeyondLastLine: false,
    renderWhitespace: 'none',
    tabSize: 2,
  })

  let timer = 0
  editor.onDidChangeModelContent(() => {
    clearTimeout(timer)
    timer = window.setTimeout(() => onChange(editor.getValue()), 220)
  })

  let decorations: string[] = []

  return {
    editor,
    setDiags(diags) {
      const model = editor.getModel()
      if (!model) return
      monaco.editor.setModelMarkers(
        model,
        'swisscam',
        diags.map((d) => ({
          startLineNumber: d.line + 1,
          endLineNumber: d.line + 1,
          startColumn: d.col + 1,
          endColumn: d.col + 1 + Math.max(1, d.length),
          message: d.channel ? `[$${d.channel}] ${d.message}` : d.message,
          severity:
            d.severity === 'error'
              ? monaco.MarkerSeverity.Error
              : d.severity === 'warning'
                ? monaco.MarkerSeverity.Warning
                : monaco.MarkerSeverity.Info,
        })),
      )
    },
    highlight(line) {
      const model = editor.getModel()
      if (!model) return
      if (line === null) {
        decorations = editor.deltaDecorations(decorations, [])
        return
      }
      decorations = editor.deltaDecorations(decorations, [
        {
          range: new monaco.Range(line + 1, 1, line + 1, 1),
          options: {
            isWholeLine: true,
            className: 'current-line',
            linesDecorationsClassName: 'current-line-margin',
          },
        },
      ])
      editor.revealLineInCenterIfOutsideViewport(line + 1)
    },
    goTo(line) {
      editor.revealLineInCenter(line + 1)
      editor.setPosition({ lineNumber: line + 1, column: 1 })
      editor.focus()
    },
  }
}
