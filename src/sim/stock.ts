/**
 * Осесимметричная модель заготовки-прутка.
 *
 * Пруток описывается двумя профилями вдоль оси Z: наружным радиусом ro[i]
 * и радиусом осевого отверстия ri[i]. Этого достаточно для точения, подрезки,
 * канавок, отрезки и осевого сверления — то есть для подавляющей части
 * программы станка продольного точения. Поперечное сверление и фрезеровку
 * приводным инструментом модель не описывает: такие проходы помечаются
 * отдельно и показываются только траекторией.
 */
export class Stock {
  readonly zMin: number
  readonly zMax: number
  readonly dz: number
  readonly n: number
  readonly barRadius: number
  /** Наружный радиус, мм */
  ro: Float32Array
  /** Радиус осевого отверстия, мм */
  ri: Float32Array
  /** Снятый объём, мм³ */
  removed = 0
  /** Z, на котором деталь отрезана (null — ещё цела) */
  cutoffZ: number | null = null

  constructor(diameter: number, zMin: number, zMax: number, dz = 0.02) {
    this.barRadius = diameter / 2
    this.zMin = zMin
    this.zMax = zMax
    this.dz = dz
    this.n = Math.max(2, Math.ceil((zMax - zMin) / dz) + 1)
    this.ro = new Float32Array(this.n).fill(this.barRadius)
    this.ri = new Float32Array(this.n)
  }

  index(z: number): number {
    return Math.round((z - this.zMin) / this.dz)
  }

  z(i: number): number {
    return this.zMin + i * this.dz
  }

  clone(): Stock {
    const s = new Stock(this.barRadius * 2, this.zMin, this.zMax, this.dz)
    s.ro.set(this.ro)
    s.ri.set(this.ri)
    s.removed = this.removed
    s.cutoffZ = this.cutoffZ
    return s
  }

  private ringVolume(rOuterBefore: number, rOuterAfter: number, rInner: number): number {
    const a = Math.max(rOuterBefore, rInner)
    const b = Math.max(rOuterAfter, rInner)
    return Math.PI * (a * a - b * b) * this.dz
  }

  /**
   * Наружный проход: инструмент идёт от (z0,r0) к (z1,r1), ширина режущей кромки width.
   * Материал снаружи линии убирается.
   */
  turn(z0: number, r0: number, z1: number, r1: number, width = 0): number {
    const half = width / 2
    const lo = Math.min(z0, z1) - half
    const hi = Math.max(z0, z1) + half
    let i0 = Math.max(0, this.index(lo))
    let i1 = Math.min(this.n - 1, this.index(hi))
    if (i1 < i0) {
      const c = Math.max(0, Math.min(this.n - 1, this.index((z0 + z1) / 2)))
      i0 = i1 = c
    }
    let vol = 0
    const dzTotal = z1 - z0
    for (let i = i0; i <= i1; i++) {
      const z = this.z(i)
      let t = dzTotal === 0 ? 0 : (z - z0) / dzTotal
      t = t < 0 ? 0 : t > 1 ? 1 : t
      const r = r0 + (r1 - r0) * t
      if (r < this.ro[i]!) {
        vol += this.ringVolume(this.ro[i]!, r, this.ri[i]!)
        this.ro[i] = Math.max(r, 0)
        if (r <= 1e-4 && this.cutoffZ === null) this.cutoffZ = z
      }
    }
    this.removed += vol
    return vol
  }

  /** Осевое сверление/растачивание: отверстие радиуса r от z0 до z1 */
  bore(z0: number, z1: number, r: number): number {
    const lo = Math.min(z0, z1)
    const hi = Math.max(z0, z1)
    const i0 = Math.max(0, this.index(lo))
    const i1 = Math.min(this.n - 1, this.index(hi))
    let vol = 0
    for (let i = i0; i <= i1; i++) {
      if (r > this.ri[i]!) {
        const a = Math.min(r, this.ro[i]!)
        const b = this.ri[i]!
        vol += Math.PI * (a * a - b * b) * this.dz
        this.ri[i] = a
      }
    }
    this.removed += vol
    return vol
  }

  /** Профиль для отрисовки, прорежённый до maxPoints точек */
  outline(maxPoints = 2000): { z: Float32Array; ro: Float32Array; ri: Float32Array } {
    const step = Math.max(1, Math.ceil(this.n / maxPoints))
    const count = Math.ceil(this.n / step)
    const z = new Float32Array(count)
    const ro = new Float32Array(count)
    const ri = new Float32Array(count)
    for (let j = 0, i = 0; j < count; j++, i += step) {
      z[j] = this.z(i)
      ro[j] = this.ro[i]!
      ri[j] = this.ri[i]!
    }
    return { z, ro, ri }
  }

  /** Объём оставшегося материала, мм³ */
  volume(): number {
    let v = 0
    for (let i = 0; i < this.n; i++) {
      const a = this.ro[i]!
      const b = Math.min(this.ri[i]!, a)
      v += Math.PI * (a * a - b * b) * this.dz
    }
    return v
  }
}
