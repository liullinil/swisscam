import type { Block, Diag, Op, Pos } from './types.ts'
import { posClone } from './types.ts'
import type { Dialect } from './dialect.ts'
import type { ChannelSource } from './lexer.ts'

interface Modal {
  motion: number
  units: 'mm' | 'inch'
  feedPerRev: boolean
  feed: number
  css: boolean
  /** об/мин при G97 или м/мин при G96 */
  sValue: number
  rpmCap: number
  wcs: number
  tool: number
  absolute: boolean
  comp: number
}

/** Циклы, которые мы распознаём, но пока не моделируем */
const CANNED = new Set([70, 71, 72, 73, 74, 75, 76, 81, 82, 83, 84, 85, 86, 87, 88, 89])

function num(block: Block, letter: string): number | null {
  for (let i = block.words.length - 1; i >= 0; i--) {
    const w = block.words[i]!
    if (w.letter === letter) return w.value
  }
  return null
}

function all(block: Block, letter: string): number[] {
  return block.words.filter((w) => w.letter === letter).map((w) => w.value)
}

export interface ChannelResult {
  id: string
  name: string
  ops: Op[]
  /** Суммарное время без учёта ожиданий, с */
  rawTime: number
}

export interface InterpResult {
  channels: ChannelResult[]
  diags: Diag[]
}

export interface InterpOptions {
  dialect: Dialect
  /** Диаметр прутка — от него считаются обороты при G96 в начале программы */
  barDiameter: number
}

const INCH = 25.4

export function interpretChannel(src: ChannelSource, opt: InterpOptions, diags: Diag[]): ChannelResult {
  const d = opt.dialect
  const spindle: 'main' | 'sub' = src.id === '2' ? 'sub' : 'main'
  const m: Modal = {
    motion: 0,
    units: 'mm',
    feedPerRev: d.feedPerRevDefault,
    feed: 0,
    css: false,
    sValue: 0,
    rpmCap: d.maxRpm,
    wcs: 54,
    tool: 0,
    absolute: true,
    comp: 40,
  }
  let pos: Pos = { x: opt.barDiameter, y: 0, z: 0, c: 0 }
  const ops: Op[] = []
  let rawTime = 0

  const push = (op: Op) => {
    ops.push(op)
    rawTime += op.duration
  }

  const currentRpm = (diameter: number): number => {
    if (!m.css) return Math.min(m.sValue, m.rpmCap)
    const dia = Math.max(Math.abs(diameter), 0.01)
    const rpm = (m.sValue * 1000) / (Math.PI * dia)
    return Math.min(rpm, m.rpmCap)
  }

  for (let bi = 0; bi < src.blocks.length; bi++) {
    const b = src.blocks[bi]!
    if (b.blockDelete) continue
    if (b.macro) {
      diags.push({
        line: b.line, col: 0, length: b.raw.length, severity: 'info', channel: src.id,
        message: 'Макрокоманда не исполняется в симуляции',
      })
      continue
    }
    if (b.words.length === 0 && !b.sync) continue

    const gs = all(b, 'G')
    const ms = all(b, 'M')
    const k = m.units === 'inch' ? INCH : 1

    let hasMotion = false
    let dwellSec = 0
    let refReturn = false
    for (const g of gs) {
      const gi = Math.round(g * 10) / 10
      switch (gi) {
        case 0: case 1: case 2: case 3:
          m.motion = gi; hasMotion = true; break
        case 4: {
          const p = num(b, 'P')
          const x = num(b, 'X') ?? num(b, 'U')
          dwellSec = p !== null ? p / 1000 : x !== null ? x : 0
          break
        }
        case 20: m.units = 'inch'; break
        case 21: m.units = 'mm'; break
        case 28: case 30: refReturn = true; break
        case 40: case 41: case 42: m.comp = gi; break
        case 50: {
          const s = num(b, 'S')
          if (s !== null) m.rpmCap = Math.min(s, d.maxRpm)
          break
        }
        case 94: case 98: m.feedPerRev = false; break
        case 95: case 99: m.feedPerRev = true; break
        case 96: m.css = true; break
        case 97: m.css = false; break
        case 54: case 55: case 56: case 57: case 58: case 59: m.wcs = gi; break
        case 90: m.absolute = true; break
        case 91: m.absolute = false; break
        case 32: case 33: m.motion = 32; hasMotion = true; break
        case 7.1: case 12.1: case 13.1: case 17: case 18: case 19: break
        default:
          if (CANNED.has(Math.trunc(gi))) {
            diags.push({
              line: b.line, col: 0, length: b.raw.length, severity: 'warning', channel: src.id,
              message: `Цикл G${gi} распознан, но пока не моделируется — траектория не будет учтена`,
            })
          } else {
            diags.push({
              line: b.line, col: 0, length: b.raw.length, severity: 'warning', channel: src.id,
              message: `Неизвестный код G${gi}`,
            })
          }
      }
    }

    const f = num(b, 'F')
    if (f !== null) m.feed = f * k
    const s = num(b, 'S')
    if (s !== null) m.sValue = s

    const t = num(b, 'T')
    if (t !== null) {
      const toolNo = Math.trunc(Math.abs(t) / 100) || Math.trunc(Math.abs(t))
      if (toolNo !== m.tool) {
        m.tool = toolNo
        push({
          kind: 'tool', channel: src.id, index: bi, line: b.line,
          duration: d.toolChangeTime, tool: toolNo, spindle,
          text: `T${String(Math.trunc(t)).padStart(4, '0')}`,
        })
      }
    }

    for (const mc of ms) {
      const code = Math.trunc(mc)
      if (code >= d.waitMRange[0] && code <= d.waitMRange[1]) {
        push({ kind: 'wait', channel: src.id, index: bi, line: b.line, duration: 0, waitTag: `M${code}`, spindle })
      } else if (d.cutoffM.includes(code)) {
        push({ kind: 'cutoff', channel: src.id, index: bi, line: b.line, duration: 0, spindle, text: `M${code}` })
      } else if (code === 30 || code === 2 || code === 99) {
        push({ kind: 'end', channel: src.id, index: bi, line: b.line, duration: 0, spindle, text: `M${code}` })
      } else {
        push({ kind: 'misc', channel: src.id, index: bi, line: b.line, duration: 0, spindle, text: `M${code}` })
      }
    }

    if (b.sync) {
      push({ kind: 'wait', channel: src.id, index: bi, line: b.line, duration: 0, waitTag: `!${b.sync}`, spindle })
    }

    if (dwellSec > 0) {
      push({ kind: 'dwell', channel: src.id, index: bi, line: b.line, duration: dwellSec, spindle, text: `${dwellSec.toFixed(3)} с` })
    }

    const X = num(b, 'X'), U = num(b, 'U')
    const Y = num(b, 'Y'), V = num(b, 'V')
    const Z = num(b, 'Z'), W = num(b, 'W')
    const C = num(b, 'C'), H = num(b, 'H')
    const I = num(b, 'I'), K = num(b, 'K'), R = num(b, 'R')

    const hasAxis = [X, U, Y, V, Z, W, C, H].some((v) => v !== null)
    if (refReturn || !hasAxis) continue
    void hasMotion

    const to = posClone(pos)
    if (X !== null) to.x = m.absolute ? X * k : pos.x + X * k
    if (U !== null) to.x = pos.x + U * k
    if (Y !== null) to.y = m.absolute ? Y * k : pos.y + Y * k
    if (V !== null) to.y = pos.y + V * k
    if (Z !== null) to.z = m.absolute ? Z * k : pos.z + Z * k
    if (W !== null) to.z = pos.z + W * k
    if (C !== null) to.c = m.absolute ? C : pos.c + C
    if (H !== null) to.c = pos.c + H

    const rx = d.diameterX ? 0.5 : 1
    const dx = (to.x - pos.x) * rx
    const dy = to.y - pos.y
    const dz = to.z - pos.z

    const rpm = currentRpm(to.x)
    let duration: number
    let length = Math.hypot(dx, dy, dz)
    let move: Op['move'] = 'feed'
    let arc: Op['arc']

    if (m.motion === 0) {
      move = 'rapid'
      duration = Math.max(
        Math.abs(dx) / d.rapid.x,
        Math.abs(dy) / d.rapid.y,
        Math.abs(dz) / d.rapid.z,
        Math.abs(to.c - pos.c) / d.rapid.c,
      ) * 60
    } else {
      if (m.motion === 2 || m.motion === 3) {
        move = 'arc'
        const ccw = m.motion === 3
        const sx = pos.x * rx, sz = pos.z
        const ex = to.x * rx, ez = to.z
        let cx: number, cz: number
        if (I !== null || K !== null) {
          cx = sx + (I ?? 0) * k
          cz = sz + (K ?? 0) * k
        } else if (R !== null) {
          const rr = R * k
          const mx = (sx + ex) / 2, mz = (sz + ez) / 2
          const chord = Math.hypot(ex - sx, ez - sz) || 1
          const h2 = rr * rr - (chord / 2) * (chord / 2)
          const h = h2 > 0 ? Math.sqrt(h2) : 0
          const ux = -(ez - sz) / chord, uz = (ex - sx) / chord
          const sign = (rr >= 0 ? 1 : -1) * (ccw ? 1 : -1)
          cx = mx + ux * h * sign
          cz = mz + uz * h * sign
        } else {
          cx = sx; cz = sz
          diags.push({
            line: b.line, col: 0, length: b.raw.length, severity: 'error', channel: src.id,
            message: 'Дуга задана без I/K и без R',
          })
        }
        arc = { cx, cz, ccw }
        const r0 = Math.hypot(sx - cx, sz - cz)
        const r1 = Math.hypot(ex - cx, ez - cz)
        if (Math.abs(r0 - r1) > 0.02) {
          diags.push({
            line: b.line, col: 0, length: b.raw.length, severity: 'warning', channel: src.id,
            message: `Радиусы дуги не сходятся: ${r0.toFixed(3)} и ${r1.toFixed(3)} мм`,
          })
        }
        const a0 = Math.atan2(sx - cx, sz - cz)
        const a1 = Math.atan2(ex - cx, ez - cz)
        let sweep = a1 - a0
        if (ccw) { while (sweep <= 1e-9) sweep += Math.PI * 2 } else { while (sweep >= -1e-9) sweep -= Math.PI * 2 }
        length = Math.abs(sweep) * r0
      } else if (m.motion === 32) {
        move = 'thread'
      }
      const feedMmMin = m.feedPerRev ? m.feed * rpm : m.feed
      duration = feedMmMin > 0 ? (length / feedMmMin) * 60 : 0
      if (feedMmMin <= 0) {
        diags.push({
          line: b.line, col: 0, length: b.raw.length, severity: 'warning', channel: src.id,
          message: 'Рабочий ход без заданной подачи F',
        })
      }
    }

    push({
      kind: 'move', channel: src.id, index: bi, line: b.line,
      duration, move, from: posClone(pos), to: posClone(to), arc,
      feed: m.feedPerRev ? m.feed * rpm : m.feed, rpm, tool: m.tool, spindle,
    })
    pos = to
  }

  return { id: src.id, name: src.name, ops, rawTime }
}

export function interpret(channels: ChannelSource[], opt: InterpOptions): InterpResult {
  const diags: Diag[] = []
  return {
    channels: channels.map((c) => interpretChannel(c, opt, diags)),
    diags,
  }
}
