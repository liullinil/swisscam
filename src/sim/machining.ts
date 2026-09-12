import type { Op } from '../core/types.ts'
import type { Scheduled, Timeline } from '../core/sync.ts'
import { Stock } from './stock.ts'
import type { Tool } from './tools.ts'

export interface SimOptions {
  barDiameter: number
  /** Длина моделируемого участка прутка от торца назад, мм */
  barLength: number
  /** Шаг сетки по Z, мм */
  gridStep: number
  tools: Map<number, Tool>
  /**
   * Плоскость отрезки в координатах прутка, мм. Нужна для пересчёта координат
   * противошпинделя: z_пруток = cutPlane − z_противошпинделя.
   */
  cutPlane: number
}

export interface StepInfo {
  index: number
  op: Op
  start: number
  end: number
  volume: number
  /** Съём материала, мм³/мин — полезно для оценки нагрузки на инструмент */
  mrr: number
  modelled: boolean
}

interface Snapshot {
  index: number
  ro: Float32Array
  ri: Float32Array
  removed: number
  cutoffZ: number | null
}

const SNAPSHOT_EVERY = 64

/** Прогон программы по заготовке с возможностью перемотки в любой кадр. */
export class Simulation {
  readonly items: Scheduled[]
  readonly opt: SimOptions
  readonly stock: Stock
  readonly steps: StepInfo[] = []
  /** Плоскость отрезки, найденная за полный прогон (null — деталь не отрезана) */
  finalCutoffZ: number | null = null
  private snapshots: Snapshot[] = []
  private cursor = 0

  constructor(timeline: Timeline, opt: SimOptions) {
    this.items = timeline.items
    this.opt = opt
    this.stock = new Stock(opt.barDiameter, -opt.barLength, 2, opt.gridStep)
    this.snap()
    this.runAll()
    this.rewind()
  }

  private snap() {
    this.snapshots.push({
      index: this.cursor,
      ro: this.stock.ro.slice(),
      ri: this.stock.ri.slice(),
      removed: this.stock.removed,
      cutoffZ: this.stock.cutoffZ,
    })
  }

  private restore(s: Snapshot) {
    this.stock.ro.set(s.ro)
    this.stock.ri.set(s.ri)
    this.stock.removed = s.removed
    this.stock.cutoffZ = s.cutoffZ
    this.cursor = s.index
  }

  /** Проходит всю программу, собирая статистику по кадрам и опорные снимки. */
  private runAll() {
    while (this.cursor < this.items.length) {
      const info = this.applyOne(this.items[this.cursor]!, this.cursor)
      this.steps.push(info)
      this.cursor++
      if (this.cursor % SNAPSHOT_EVERY === 0) this.snap()
    }
    this.finalCutoffZ = this.stock.cutoffZ
  }

  rewind() {
    this.restore(this.snapshots[0]!)
  }

  /** Перематывает модель к состоянию после кадра index (включительно). */
  seek(index: number) {
    const target = Math.max(-1, Math.min(index, this.items.length - 1))
    let best = this.snapshots[0]!
    for (const s of this.snapshots) {
      if (s.index <= target + 1 && s.index >= best.index) best = s
    }
    if (this.cursor > target + 1 || this.cursor < best.index) this.restore(best)
    while (this.cursor <= target) {
      this.applyOne(this.items[this.cursor]!, this.cursor)
      this.cursor++
    }
  }

  /** Индекс кадра, активного в момент времени t (секунды) */
  indexAtTime(t: number): number {
    let lo = 0, hi = this.items.length - 1, res = -1
    while (lo <= hi) {
      const mid = (lo + hi) >> 1
      if (this.items[mid]!.start <= t) { res = mid; lo = mid + 1 } else hi = mid - 1
    }
    return res
  }

  private applyOne(item: Scheduled, index: number): StepInfo {
    const op = item.op
    const info: StepInfo = { index, op, start: item.start, end: item.end, volume: 0, mrr: 0, modelled: false }
    if (op.kind !== 'move' || !op.from || !op.to || op.move === 'rapid') return info

    const tool = this.opt.tools.get(op.tool ?? 0)
    const kind = tool?.kind ?? 'turn'
    if (kind === 'live') return info

    const sub = op.spindle === 'sub'
    const cut = this.stock.cutoffZ ?? this.opt.cutPlane
    const mapZ = (z: number) => (sub ? cut - z : z)

    const z0 = mapZ(op.from.z)
    const z1 = mapZ(op.to.z)
    const r0 = Math.abs(op.from.x) / 2
    const r1 = Math.abs(op.to.x) / 2

    let vol = 0
    if (kind === 'drill') {
      const rr = (tool?.diameter ?? 3) / 2
      vol = this.stock.bore(z0, z1, rr)
    } else {
      const width = tool?.width ?? 0
      vol = this.stock.turn(z0, r0, z1, r1, width)
    }
    info.volume = vol
    info.modelled = true
    const dt = item.end - item.start
    info.mrr = dt > 0 ? (vol / dt) * 60 : 0
    return info
  }
}
