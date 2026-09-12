import type { Scheduled } from '../core/sync.ts'
import type { Stock } from '../sim/stock.ts'

export interface PathSeg {
  channel: string
  kind: 'rapid' | 'feed' | 'arc' | 'thread'
  /** Плоские точки [z0,r0, z1,r1, …] в координатах прутка */
  pts: number[]
  line: number
  index: number
}

export const CHANNEL_COLORS: Record<string, string> = {
  '1': '#4ea3ff',
  '2': '#37d39a',
  '3': '#c47bff',
}

/** Разворачивает операции в плоские полилинии для отрисовки. */
export function buildPaths(items: Scheduled[], cutPlane: number, cutoffZ: number | null): PathSeg[] {
  const out: PathSeg[] = []
  const cut = cutoffZ ?? cutPlane
  for (let i = 0; i < items.length; i++) {
    const op = items[i]!.op
    if (op.kind !== 'move' || !op.from || !op.to) continue
    const sub = op.spindle === 'sub'
    const mz = (z: number) => (sub ? cut - z : z)
    const r0 = op.from.x / 2
    const r1 = op.to.x / 2
    const z0 = mz(op.from.z)
    const z1 = mz(op.to.z)
    let pts: number[]
    if (op.move === 'arc' && op.arc) {
      const cx = op.arc.cx
      const cz = sub ? cut - op.arc.cz : op.arc.cz
      const rad = Math.hypot(r0 - cx, z0 - cz)
      let a0 = Math.atan2(r0 - cx, z0 - cz)
      const a1 = Math.atan2(r1 - cx, z1 - cz)
      let sweep = a1 - a0
      const ccw = sub ? !op.arc.ccw : op.arc.ccw
      if (ccw) { while (sweep <= 1e-9) sweep += Math.PI * 2 } else { while (sweep >= -1e-9) sweep -= Math.PI * 2 }
      const steps = Math.max(4, Math.ceil(Math.abs(sweep) / 0.12))
      pts = []
      for (let s = 0; s <= steps; s++) {
        const a = a0 + (sweep * s) / steps
        pts.push(cz + rad * Math.cos(a), cx + rad * Math.sin(a))
      }
      a0 = a1
    } else {
      pts = [z0, r0, z1, r1]
    }
    out.push({ channel: op.channel, kind: op.move ?? 'feed', pts, line: op.line, index: i })
  }
  return out
}

export interface Marker {
  channel: string
  z: number
  r: number
  tool: number
}

export interface Scene {
  stock: Stock
  paths: PathSeg[]
  markers: Marker[]
  showRapid: boolean
  showPaths: boolean
  /** Кадры, уже пройденные симуляцией — рисуются ярче */
  upto: number
}

export class Backplot {
  private ctx: CanvasRenderingContext2D
  private scale = 8
  private ox = 0
  private oy = 0
  private dragging = false
  private lastX = 0
  private lastY = 0
  private scene: Scene | null = null

  constructor(private canvas: HTMLCanvasElement) {
    const ctx = canvas.getContext('2d')
    if (!ctx) throw new Error('Canvas 2D недоступен')
    this.ctx = ctx

    canvas.addEventListener('wheel', (e) => {
      e.preventDefault()
      const rect = canvas.getBoundingClientRect()
      const mx = e.clientX - rect.left
      const my = e.clientY - rect.top
      const k = e.deltaY < 0 ? 1.15 : 1 / 1.15
      this.ox = mx - (mx - this.ox) * k
      this.oy = my - (my - this.oy) * k
      this.scale *= k
      this.draw()
    }, { passive: false })

    canvas.addEventListener('pointerdown', (e) => {
      this.dragging = true
      this.lastX = e.clientX
      this.lastY = e.clientY
      canvas.setPointerCapture(e.pointerId)
    })
    canvas.addEventListener('pointermove', (e) => {
      if (!this.dragging) return
      this.ox += e.clientX - this.lastX
      this.oy += e.clientY - this.lastY
      this.lastX = e.clientX
      this.lastY = e.clientY
      this.draw()
    })
    canvas.addEventListener('pointerup', (e) => {
      this.dragging = false
      canvas.releasePointerCapture(e.pointerId)
    })

    new ResizeObserver(() => this.resize()).observe(canvas)
  }

  private resize() {
    const dpr = window.devicePixelRatio || 1
    const w = this.canvas.clientWidth
    const h = this.canvas.clientHeight
    if (w === 0 || h === 0) return
    this.canvas.width = Math.round(w * dpr)
    this.canvas.height = Math.round(h * dpr)
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    this.draw()
  }

  setScene(scene: Scene) {
    this.scene = scene
    this.draw()
  }

  fit() {
    const s = this.scene
    if (!s) return
    const w = this.canvas.clientWidth || 800
    const h = this.canvas.clientHeight || 400
    const zMin = s.stock.zMin
    const zMax = s.stock.zMax
    const rMax = Math.max(s.stock.barRadius * 1.6, 2)
    const sx = (w - 60) / Math.max(zMax - zMin, 1)
    const sy = (h - 40) / Math.max(rMax * 2, 1)
    this.scale = Math.min(sx, sy)
    this.ox = 30 - zMin * this.scale
    this.oy = h / 2
    this.draw()
  }

  private sx(z: number): number { return this.ox + z * this.scale }
  private sy(r: number): number { return this.oy - r * this.scale }

  draw() {
    const ctx = this.ctx
    const w = this.canvas.clientWidth
    const h = this.canvas.clientHeight
    ctx.clearRect(0, 0, w, h)
    ctx.fillStyle = '#0f1216'
    ctx.fillRect(0, 0, w, h)
    const s = this.scene
    if (!s) return

    this.drawGrid(w, h)
    this.drawStock(s.stock)
    if (s.showPaths) this.drawPaths(s)
    this.drawMarkers(s.markers)
    this.drawAxis(w)
  }

  private drawGrid(w: number, h: number) {
    const ctx = this.ctx
    // Шаг сетки — круглое число миллиметров, дающее не меньше 40 px
    const targets = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100]
    const step = targets.find((t) => t * this.scale >= 40) ?? 100
    ctx.strokeStyle = '#1b2028'
    ctx.fillStyle = '#4a5262'
    ctx.lineWidth = 1
    ctx.font = '10px "Segoe UI", sans-serif'
    const z0 = Math.floor((-this.ox / this.scale) / step) * step
    const z1 = (w - this.ox) / this.scale
    for (let z = z0; z <= z1; z += step) {
      const x = Math.round(this.sx(z)) + 0.5
      ctx.beginPath()
      ctx.moveTo(x, 0)
      ctx.lineTo(x, h)
      ctx.stroke()
      ctx.fillText(z.toFixed(step < 1 ? 1 : 0), x + 3, h - 4)
    }
  }

  private drawAxis(w: number) {
    const ctx = this.ctx
    ctx.strokeStyle = '#3a4250'
    ctx.setLineDash([6, 4])
    ctx.beginPath()
    ctx.moveTo(0, Math.round(this.oy) + 0.5)
    ctx.lineTo(w, Math.round(this.oy) + 0.5)
    ctx.stroke()
    ctx.setLineDash([])
  }

  private drawStock(stock: Stock) {
    const ctx = this.ctx
    const { z, ro, ri } = stock.outline(1600)
    for (const sign of [1, -1]) {
      ctx.beginPath()
      ctx.moveTo(this.sx(z[0]!), this.sy(0))
      for (let i = 0; i < z.length; i++) ctx.lineTo(this.sx(z[i]!), this.sy(sign * ro[i]!))
      ctx.lineTo(this.sx(z[z.length - 1]!), this.sy(0))
      ctx.closePath()
      ctx.fillStyle = sign > 0 ? '#39414f' : '#2f3745'
      ctx.fill()
      ctx.strokeStyle = '#8d97a8'
      ctx.lineWidth = 1
      ctx.stroke()
    }
    // Осевое отверстие
    let hasHole = false
    for (let i = 0; i < ri.length; i++) if (ri[i]! > 0) { hasHole = true; break }
    if (hasHole) {
      ctx.beginPath()
      ctx.moveTo(this.sx(z[0]!), this.sy(ri[0]!))
      for (let i = 0; i < z.length; i++) ctx.lineTo(this.sx(z[i]!), this.sy(ri[i]!))
      for (let i = z.length - 1; i >= 0; i--) ctx.lineTo(this.sx(z[i]!), this.sy(-ri[i]!))
      ctx.closePath()
      ctx.fillStyle = '#0f1216'
      ctx.fill()
      ctx.strokeStyle = '#5d6676'
      ctx.stroke()
    }
  }

  private drawPaths(s: Scene) {
    const ctx = this.ctx
    ctx.lineWidth = 1.2
    for (const p of s.paths) {
      if (p.kind === 'rapid' && !s.showRapid) continue
      const done = p.index <= s.upto
      ctx.globalAlpha = done ? 1 : 0.28
      if (p.kind === 'rapid') {
        ctx.strokeStyle = '#6b7484'
        ctx.setLineDash([4, 4])
      } else {
        ctx.strokeStyle = CHANNEL_COLORS[p.channel] ?? '#dfe4ec'
        ctx.setLineDash(p.kind === 'thread' ? [2, 2] : [])
      }
      ctx.beginPath()
      for (let i = 0; i < p.pts.length; i += 2) {
        const x = this.sx(p.pts[i]!)
        const y = this.sy(p.pts[i + 1]!)
        if (i === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.stroke()
    }
    ctx.setLineDash([])
    ctx.globalAlpha = 1
  }

  private drawMarkers(markers: Marker[]) {
    const ctx = this.ctx
    for (const m of markers) {
      const x = this.sx(m.z)
      const y = this.sy(m.r)
      const color = CHANNEL_COLORS[m.channel] ?? '#fff'
      ctx.fillStyle = color
      ctx.strokeStyle = '#0f1216'
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(x, y)
      ctx.lineTo(x - 6, y - 12)
      ctx.lineTo(x + 6, y - 12)
      ctx.closePath()
      ctx.fill()
      ctx.stroke()
      ctx.fillStyle = color
      ctx.font = '11px "Segoe UI", sans-serif'
      ctx.fillText(`T${m.tool} $${m.channel}`, x + 8, y - 14)
    }
  }
}
