import type { Diag, Op } from './types.ts'
import type { ChannelResult } from './interp.ts'

export interface Scheduled {
  op: Op
  start: number
  end: number
}

export interface Timeline {
  /** Все операции всех каналов, отсортированные по времени старта */
  items: Scheduled[]
  /** По каналам, в порядке исполнения */
  byChannel: Map<string, Scheduled[]>
  /** Ожидания: сколько канал простоял на каждом коде */
  waits: { channel: string; tag: string; from: number; to: number; line: number }[]
  totalTime: number
  diags: Diag[]
}

/**
 * Раскладывает операции каналов по времени с учётом кодов ожидания.
 * Код ожидания — рандеву: канал стоит, пока на тот же код не придут все каналы,
 * в которых этот код вообще встречается.
 */
export function schedule(channels: ChannelResult[]): Timeline {
  const diags: Diag[] = []
  const items: Scheduled[] = []
  const byChannel = new Map<string, Scheduled[]>()
  const waits: Timeline['waits'] = []

  // Кто участвует в каком коде ожидания
  const participants = new Map<string, Set<string>>()
  for (const ch of channels) {
    byChannel.set(ch.id, [])
    for (const op of ch.ops) {
      if (op.kind === 'wait' && op.waitTag) {
        let set = participants.get(op.waitTag)
        if (!set) participants.set(op.waitTag, (set = new Set()))
        set.add(ch.id)
      }
    }
  }

  const cursor = new Map<string, number>()
  const time = new Map<string, number>()
  const blocked = new Map<string, { tag: string; since: number; line: number } | null>()
  for (const ch of channels) {
    cursor.set(ch.id, 0)
    time.set(ch.id, 0)
    blocked.set(ch.id, null)
  }

  const finished = (ch: ChannelResult) => cursor.get(ch.id)! >= ch.ops.length

  let guard = 0
  for (;;) {
    if (++guard > 2_000_000) {
      diags.push({ line: 0, col: 0, length: 0, severity: 'error', message: 'Планировщик не сошёлся — слишком много шагов' })
      break
    }

    let progressed = false
    for (const ch of channels) {
      if (blocked.get(ch.id)) continue
      while (!finished(ch)) {
        const i = cursor.get(ch.id)!
        const op = ch.ops[i]!
        if (op.kind === 'wait' && op.waitTag) {
          const others = participants.get(op.waitTag)!
          if (others.size <= 1) {
            // Код ожидания встречается только в одном канале — исполнять нечему
            diags.push({
              line: op.line, col: 0, length: 0, severity: 'warning', channel: ch.id,
              message: `Коду ожидания ${op.waitTag} нет пары в других каналах`,
            })
            cursor.set(ch.id, i + 1)
            progressed = true
            continue
          }
          blocked.set(ch.id, { tag: op.waitTag, since: time.get(ch.id)!, line: op.line })
          break
        }
        const start = time.get(ch.id)!
        const end = start + op.duration
        const item: Scheduled = { op, start, end }
        items.push(item)
        byChannel.get(ch.id)!.push(item)
        time.set(ch.id, end)
        cursor.set(ch.id, i + 1)
        progressed = true
      }
    }

    // Снимаем барьеры, на которые пришли все участники
    let released = false
    const tags = new Set<string>()
    for (const ch of channels) {
      const b = blocked.get(ch.id)
      if (b) tags.add(b.tag)
    }
    for (const tag of tags) {
      const need = participants.get(tag)!
      const arrived = channels.filter((c) => blocked.get(c.id)?.tag === tag)
      const arrivedIds = new Set(arrived.map((c) => c.id))
      const allHere = [...need].every((id) => arrivedIds.has(id) || finished(channels.find((c) => c.id === id)!))
      if (!allHere) continue
      const releaseAt = Math.max(...arrived.map((c) => blocked.get(c.id)!.since))
      for (const c of arrived) {
        const b = blocked.get(c.id)!
        if (releaseAt > b.since) {
          waits.push({ channel: c.id, tag, from: b.since, to: releaseAt, line: b.line })
        }
        time.set(c.id, releaseAt)
        cursor.set(c.id, cursor.get(c.id)! + 1)
        blocked.set(c.id, null)
      }
      released = true
    }

    const allDone = channels.every((c) => finished(c) && !blocked.get(c.id))
    if (allDone) break
    if (!progressed && !released) {
      for (const ch of channels) {
        const b = blocked.get(ch.id)
        if (b) {
          diags.push({
            line: b.line, col: 0, length: 0, severity: 'error', channel: ch.id,
            message: `Взаимная блокировка: канал ждёт ${b.tag}, а парный канал туда не приходит`,
          })
        }
      }
      break
    }
  }

  items.sort((a, b) => a.start - b.start)
  const totalTime = Math.max(0, ...channels.map((c) => time.get(c.id)!))
  return { items, byChannel, waits, totalTime, diags }
}
