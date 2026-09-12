import type { ChannelResult } from '../core/interp.ts'

export type ToolKind = 'turn' | 'groove' | 'cutoff' | 'drill' | 'thread' | 'live'

export interface Tool {
  id: number
  name: string
  kind: ToolKind
  /** Ширина режущей кромки, мм — для канавочных и отрезных */
  width: number
  /** Радиус при вершине, мм */
  noseR: number
  /** Диаметр осевого инструмента, мм */
  diameter: number
}

export function defaultTool(id: number, kind: ToolKind = 'turn'): Tool {
  const base: Tool = { id, name: `T${String(id).padStart(2, '0')}`, kind, width: 0, noseR: 0.4, diameter: 3 }
  if (kind === 'groove') return { ...base, name: `T${id} канавочный`, width: 2, noseR: 0.2 }
  if (kind === 'cutoff') return { ...base, name: `T${id} отрезной`, width: 2, noseR: 0.1 }
  if (kind === 'drill') return { ...base, name: `T${id} сверло`, width: 0, noseR: 0, diameter: 3 }
  if (kind === 'thread') return { ...base, name: `T${id} резьбовой`, width: 0.2, noseR: 0.05 }
  if (kind === 'live') return { ...base, name: `T${id} приводной`, width: 0, noseR: 0, diameter: 3 }
  return base
}

/**
 * Строит таблицу инструмента по программе. Тип угадывается по характеру движений:
 * рабочий ход по оси при X≈0 — осевое сверление, рабочий ход только по X — канавка/отрезка.
 * Пользователь правит таблицу вручную, догадка нужна лишь как стартовое состояние.
 */
export function inferTools(channels: ChannelResult[]): Map<number, Tool> {
  const stats = new Map<number, { axial: number; radial: number; long: number; minX: number }>()
  for (const ch of channels) {
    for (const op of ch.ops) {
      if (op.kind !== 'move' || op.move === 'rapid' || !op.from || !op.to) continue
      const id = op.tool ?? 0
      let st = stats.get(id)
      if (!st) stats.set(id, (st = { axial: 0, radial: 0, long: 0, minX: Infinity }))
      const dx = Math.abs(op.to.x - op.from.x) / 2
      const dz = Math.abs(op.to.z - op.from.z)
      st.minX = Math.min(st.minX, Math.abs(op.to.x), Math.abs(op.from.x))
      if (dz > dx * 4) st.long += dz
      else if (dx > dz * 4) st.radial += dx
      if (dz > 0 && Math.abs(op.to.x) < 0.05 && Math.abs(op.from.x) < 0.05) st.axial += dz
    }
  }
  const tools = new Map<number, Tool>()
  for (const [id, st] of stats) {
    if (id === 0) continue
    let kind: ToolKind = 'turn'
    if (st.axial > 0.5) kind = 'drill'
    else if (st.radial > st.long) kind = st.minX <= 0.2 ? 'cutoff' : 'groove'
    tools.set(id, defaultTool(id, kind))
  }
  return tools
}
