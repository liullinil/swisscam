/**
 * Профиль станка/стойки. Всё, что отличает один диалект от другого, живёт здесь,
 * чтобы ядро интерпретатора оставалось общим.
 */
export interface Dialect {
  id: string
  name: string
  /** Пояснение к профилю, показывается в UI */
  notes: string
  /** X в кадре — диаметр (обычное для токарных станков) */
  diameterX: boolean
  /** Диапазон M-кодов, используемых как коды ожидания между каналами */
  waitMRange: [number, number]
  /** Поддерживаются метки синхронизации вида !L1 */
  bangSync: boolean
  /** M-коды отрезки/подхвата детали противошпинделем */
  cutoffM: number[]
  /** Быстрый ход, мм/мин — для оценки машинного времени */
  rapid: { x: number; y: number; z: number; c: number }
  /** Время смены инструмента (индексации), с */
  toolChangeTime: number
  /** По умолчанию подача на оборот (G99) */
  feedPerRevDefault: boolean
  /** Максимальные обороты шпинделя */
  maxRpm: number
  /** Диаметр прутка по умолчанию, мм */
  defaultBarDiameter: number
}

export const HANWHA: Dialect = {
  id: 'hanwha',
  name: 'Hanwha XD (FANUC)',
  notes:
    'Многоканальная программа FANUC: каналы разделяются заголовками $1/$2/$3, ' +
    'ожидание между каналами — парные M-коды из диапазона M100…M199. ' +
    'Диапазон задаётся параметром стойки, при необходимости поправьте его в настройках.',
  diameterX: true,
  waitMRange: [100, 199],
  bangSync: false,
  cutoffM: [80, 81],
  rapid: { x: 24000, y: 24000, z: 32000, c: 20000 },
  toolChangeTime: 0.4,
  feedPerRevDefault: true,
  maxRpm: 10000,
  defaultBarDiameter: 20,
}

export const CITIZEN: Dialect = {
  ...HANWHA,
  id: 'citizen',
  name: 'Citizen Cincom',
  notes: 'Синхронизация метками вида !1L1 / !2L1, каналы $1/$2/$3.',
  bangSync: true,
  waitMRange: [100, 199],
}

export const FANUC_GENERIC: Dialect = {
  ...HANWHA,
  id: 'fanuc',
  name: 'FANUC turn (обобщённый)',
  notes: 'Базовый токарный FANUC без специфики продольного точения.',
  waitMRange: [100, 199],
}

export const DIALECTS: Dialect[] = [HANWHA, CITIZEN, FANUC_GENERIC]

export function dialectById(id: string): Dialect {
  return DIALECTS.find((d) => d.id === id) ?? HANWHA
}
