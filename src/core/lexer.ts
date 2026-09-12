import type { Block, Word, Diag } from './types.ts'

const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'

function isDigit(ch: string): boolean {
  return ch >= '0' && ch <= '9'
}

/** Читает число вида -12.5 / +.5 / 100 начиная с позиции i. Возвращает [значение, конец]. */
function readNumber(s: string, i: number): [number, number] {
  const start = i
  if (s[i] === '+' || s[i] === '-') i++
  while (i < s.length && (isDigit(s[i]!) || s[i] === '.')) i++
  const raw = s.slice(start, i)
  const v = raw === '' || raw === '-' || raw === '+' ? NaN : Number(raw)
  return [v, i]
}

/** Читает выражение в квадратных скобках или ссылку на переменную #100 — значение не вычисляем. */
function readExpr(s: string, i: number): number {
  if (s[i] === '#') {
    i++
    if (s[i] === '[') return skipBrackets(s, i)
    while (i < s.length && isDigit(s[i]!)) i++
    return i
  }
  if (s[i] === '[') return skipBrackets(s, i)
  return i
}

function skipBrackets(s: string, i: number): number {
  let depth = 0
  for (; i < s.length; i++) {
    if (s[i] === '[') depth++
    else if (s[i] === ']') {
      depth--
      if (depth === 0) return i + 1
    }
  }
  return s.length
}

const MACRO_RE = /^\s*(IF|WHILE|GOTO|END|DO|#\d+\s*=|WHILE\s*\[)/i

/** Разбирает одну строку УП в кадр. */
export function parseLine(text: string, line: number, diags: Diag[]): Block {
  const block: Block = {
    line,
    raw: text,
    words: [],
    comments: [],
    n: null,
    programNo: null,
    blockDelete: false,
    channelHeader: null,
    sync: null,
    macro: null,
  }

  let i = 0
  // Ведущие пробелы
  while (i < text.length && (text[i] === ' ' || text[i] === '\t')) i++

  if (text[i] === '/') {
    block.blockDelete = true
    i++
  }

  // Заголовок канала $1 / $2 / $3
  const chMatch = /^\s*\$(\d+)\s*$/.exec(text)
  if (chMatch) {
    block.channelHeader = chMatch[1]!
    return block
  }

  if (MACRO_RE.test(text.slice(i))) {
    block.macro = text.slice(i).trim()
    return block
  }

  while (i < text.length) {
    const ch = text[i]!
    if (ch === ' ' || ch === '\t' || ch === '\r') {
      i++
      continue
    }
    if (ch === '(') {
      const end = text.indexOf(')', i)
      const stop = end === -1 ? text.length : end + 1
      block.comments.push(text.slice(i + 1, end === -1 ? text.length : end).trim())
      if (end === -1) {
        diags.push({ line, col: i, length: text.length - i, severity: 'warning', message: 'Комментарий не закрыт скобкой' })
      }
      i = stop
      continue
    }
    if (ch === ';') {
      block.comments.push(text.slice(i + 1).trim())
      break
    }
    if (ch === '%') {
      i++
      continue
    }
    if (ch === '!') {
      // Метка синхронизации Citizen/Star: !L1, !2L3, !3
      const m = /^![0-9]*(?:L[0-9]+)?/.exec(text.slice(i))
      const raw = m ? m[0] : '!'
      block.sync = raw.slice(1) || '1'
      i += raw.length
      continue
    }
    if (ch === '#') {
      block.macro = (block.macro ?? '') + text.slice(i).trim()
      break
    }
    const up = ch.toUpperCase()
    if (LETTERS.includes(up)) {
      const col = i
      i++
      let value: number
      let rawEnd: number
      if (text[i] === '[' || text[i] === '#') {
        rawEnd = readExpr(text, i)
        value = NaN
      } else {
        ;[value, rawEnd] = readNumber(text, i)
      }
      const raw = text.slice(col, rawEnd)
      i = rawEnd
      const word: Word = { letter: up, value, raw, col }
      if (up === 'N' && block.words.length === 0) block.n = value
      else if (up === 'O' && block.words.length === 0) block.programNo = value
      else block.words.push(word)
      if (Number.isNaN(value) && !raw.includes('[') && !raw.includes('#')) {
        diags.push({ line, col, length: raw.length, severity: 'error', message: `Адрес ${up} без числа` })
      }
      continue
    }
    diags.push({ line, col: i, length: 1, severity: 'error', message: `Недопустимый символ «${ch}»` })
    i++
  }

  return block
}

export interface ChannelSource {
  /** '1', '2', '3' */
  id: string
  name: string
  blocks: Block[]
}

export interface ParsedProgram {
  channels: ChannelSource[]
  diags: Diag[]
}

const CHANNEL_NAMES: Record<string, string> = {
  '1': '$1 главный шпиндель',
  '2': '$2 противошпиндель',
  '3': '$3 третий суппорт',
}

/**
 * Разбирает текст УП. Каналы разделяются заголовками $1/$2/$3.
 * Если заголовков нет — вся программа считается каналом $1.
 */
export function parseProgram(text: string): ParsedProgram {
  const diags: Diag[] = []
  const lines = text.split(/\r?\n/)
  const channels: ChannelSource[] = []
  let current: ChannelSource | null = null

  const ensure = (id: string): ChannelSource => {
    let c = channels.find((x) => x.id === id)
    if (!c) {
      c = { id, name: CHANNEL_NAMES[id] ?? `$${id}`, blocks: [] }
      channels.push(c)
    }
    return c
  }

  for (let i = 0; i < lines.length; i++) {
    const block = parseLine(lines[i]!, i, diags)
    if (block.channelHeader) {
      current = ensure(block.channelHeader)
      continue
    }
    if (!current) current = ensure('1')
    current.blocks.push(block)
  }

  if (channels.length === 0) channels.push({ id: '1', name: CHANNEL_NAMES['1']!, blocks: [] })
  channels.sort((a, b) => a.id.localeCompare(b.id))
  return { channels, diags }
}
