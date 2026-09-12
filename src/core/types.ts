/** Один адрес в кадре: буква + число, например X12.5 */
export interface Word {
  letter: string
  value: number
  /** Исходный текст, включая выражения вида X[#100+1] — тогда value = NaN */
  raw: string
  col: number
}

/** Разобранный кадр УП (одна строка исходника) */
export interface Block {
  /** Номер строки в исходном тексте, с нуля */
  line: number
  raw: string
  words: Word[]
  comments: string[]
  /** Nxxxx, если есть */
  n: number | null
  /** Oxxxx — номер программы */
  programNo: number | null
  /** Кадр помечен «/» — пропуск кадра */
  blockDelete: boolean
  /** Заголовок канала: $1, $2, $3 */
  channelHeader: string | null
  /** Метка синхронизации в стиле Citizen/Star: !L1, !2L3 */
  sync: string | null
  /** Макро-текст (IF/WHILE/GOTO/#100=...), который мы пока не исполняем */
  macro: string | null
}

export interface Pos {
  /** Программное X. При диаметральном программировании это диаметр. */
  x: number
  y: number
  z: number
  /** Угол оси C, градусы */
  c: number
}

export function posClone(p: Pos): Pos {
  return { x: p.x, y: p.y, z: p.z, c: p.c }
}

export type MoveKind = 'rapid' | 'feed' | 'arc' | 'thread'

export type OpKind =
  | 'move'
  | 'dwell'
  | 'tool'
  | 'spindle'
  | 'wait'
  | 'cutoff'
  | 'misc'
  | 'end'

/** Элементарное действие канала: то, что занимает время на диаграмме */
export interface Op {
  kind: OpKind
  channel: string
  /** Индекс кадра внутри канала */
  index: number
  line: number
  /** Секунды */
  duration: number
  /** Для kind==='move' */
  move?: MoveKind
  from?: Pos
  to?: Pos
  /** Центр дуги в радиусных координатах (x — радиус, не диаметр) */
  arc?: { cx: number; cz: number; ccw: boolean }
  /** Эффективная подача, мм/мин */
  feed?: number
  rpm?: number
  tool?: number
  /** Главный шпиндель или противошпиндель */
  spindle?: 'main' | 'sub'
  /** Метка ожидания для синхронизации каналов */
  waitTag?: string
  text?: string
}

export interface Diag {
  line: number
  col: number
  length: number
  severity: 'error' | 'warning' | 'info'
  message: string
  channel?: string
}
