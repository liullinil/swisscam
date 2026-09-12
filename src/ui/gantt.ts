import type { Timeline } from '../core/sync.ts'
import { CHANNEL_COLORS } from './backplot.ts'

/** Диаграмма занятости каналов: видно, кто кого ждёт и где уходит время цикла. */
export class Gantt {
  private ctx: CanvasRenderingContext2D
  private timeline: Timeline | null = null
  private time = 0

  constructor(private canvas: HTMLCanvasElement, private onSeek: (t: number) => void) {
    const ctx = canvas.getContext('2d')
    if (!ctx) throw new Error('Canvas 2D недоступен')
    this.ctx = ctx
    canvas.addEventListener('pointerdown', (e) => {
      if (!this.timeline || this.timeline.totalTime <= 0) return
      const rect = canvas.getBoundingClientRect()
      const t = ((e.clientX - rect.left) / rect.width) * this.timeline.totalTime
      this.onSeek(Math.max(0, Math.min(t, this.timeline.totalTime)))
    })
    new ResizeObserver(() => this.resize()).observe(canvas)
  }

  private resize() {
    const dpr = window.devicePixelRatio || 1
    const w = this.canvas.clientWidth
    const h = this.canvas.clientHeight
    if (!w || !h) return
    this.canvas.width = Math.round(w * dpr)
    this.canvas.height = Math.round(h * dpr)
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    this.draw()
  }

  set(timeline: Timeline) {
    this.timeline = timeline
    this.draw()
  }

  setTime(t: number) {
    this.time = t
    this.draw()
  }

  draw() {
    const ctx = this.ctx
    const w = this.canvas.clientWidth
    const h = this.canvas.clientHeight
    ctx.clearRect(0, 0, w, h)
    ctx.fillStyle = '#14171c'
    ctx.fillRect(0, 0, w, h)
    const tl = this.timeline
    if (!tl || tl.totalTime <= 0) return

    const ids = [...tl.byChannel.keys()].sort()
    const padL = 64
    const rowH = Math.min(24, (h - 18) / Math.max(ids.length, 1))
    const sx = (t: number) => padL + (t / tl.totalTime) * (w - padL - 10)

    ctx.font = '11px "Segoe UI", sans-serif'
    ids.forEach((id, row) => {
      const y = 4 + row * rowH
      ctx.fillStyle = '#8d97a8'
      ctx.fillText(`$${id}`, 8, y + rowH * 0.65)
      ctx.fillStyle = '#1b1f26'
      ctx.fillRect(padL, y, w - padL - 10, rowH - 4)

      for (const it of tl.byChannel.get(id)!) {
        if (it.end <= it.start) continue
        const x0 = sx(it.start)
        const x1 = Math.max(sx(it.end), x0 + 1)
        const op = it.op
        let color = CHANNEL_COLORS[id] ?? '#4ea3ff'
        if (op.kind === 'move' && op.move === 'rapid') color = '#4a5262'
        else if (op.kind === 'tool') color = '#ffc857'
        else if (op.kind === 'dwell') color = '#ff9d5c'
        ctx.fillStyle = color
        ctx.fillRect(x0, y, x1 - x0, rowH - 4)
      }

      for (const wt of tl.waits) {
        if (wt.channel !== id) continue
        const x0 = sx(wt.from)
        const x1 = Math.max(sx(wt.to), x0 + 1)
        ctx.fillStyle = 'rgba(255, 107, 107, 0.35)'
        ctx.fillRect(x0, y, x1 - x0, rowH - 4)
        ctx.strokeStyle = '#ff6b6b'
        ctx.setLineDash([2, 2])
        ctx.strokeRect(x0 + 0.5, y + 0.5, Math.max(x1 - x0 - 1, 1), rowH - 5)
        ctx.setLineDash([])
      }
    })

    // Шкала времени
    ctx.strokeStyle = '#2e3541'
    ctx.fillStyle = '#4a5262'
    const stepTargets = [0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60]
    const pxPerSec = (w - padL - 10) / tl.totalTime
    const step = stepTargets.find((t) => t * pxPerSec >= 55) ?? 60
    for (let t = 0; t <= tl.totalTime; t += step) {
      const x = Math.round(sx(t)) + 0.5
      ctx.beginPath()
      ctx.moveTo(x, h - 14)
      ctx.lineTo(x, h - 10)
      ctx.stroke()
      ctx.fillText(`${t.toFixed(step < 1 ? 1 : 0)}с`, x + 2, h - 3)
    }

    const cx = sx(this.time)
    ctx.strokeStyle = '#f0a020'
    ctx.lineWidth = 1.5
    ctx.beginPath()
    ctx.moveTo(cx, 0)
    ctx.lineTo(cx, h - 14)
    ctx.stroke()
    ctx.lineWidth = 1
  }
}
