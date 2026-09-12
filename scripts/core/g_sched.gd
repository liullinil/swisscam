class_name GSched
extends RefCounted

## Планировщик каналов.
##
## Код ожидания — рандеву: канал стоит на нём, пока на тот же код не придут все
## каналы, где этот код вообще встречается. Отсюда получается честное время цикла
## и видно, кто кого ждёт — обычно именно там и прячется минута на деталь.

const GUARD_LIMIT := 2_000_000


static func schedule(ops_by_channel: Dictionary) -> GTimeline:
	var tl := GTimeline.new()
	var ids: Array[String] = []
	for key in ops_by_channel.keys():
		ids.append(str(key))
	ids.sort()

	# Кто участвует в каком коде ожидания
	var participants := {}
	for id in ids:
		tl.by_channel[id] = [] as Array[GSlot]
		for op: GOp in ops_by_channel[id]:
			if op.kind == GOp.Kind.WAIT and not op.wait_tag.is_empty():
				if not participants.has(op.wait_tag):
					participants[op.wait_tag] = {}
				participants[op.wait_tag][id] = true

	var cursor := {}
	var clock := {}
	var blocked := {}
	for id in ids:
		cursor[id] = 0
		clock[id] = 0.0
		blocked[id] = null

	var guard := 0
	while true:
		guard += 1
		if guard > GUARD_LIMIT:
			tl.diags.append(GDiag.make(0, 0, 0, GDiag.Severity.ERROR, "Планировщик не сошёлся — слишком много шагов"))
			break

		var progressed := false
		for id in ids:
			if blocked[id] != null:
				continue
			var ops: Array = ops_by_channel[id]
			while cursor[id] < ops.size():
				var op: GOp = ops[cursor[id]]
				if op.kind == GOp.Kind.WAIT and not op.wait_tag.is_empty():
					var who: Dictionary = participants[op.wait_tag]
					if who.size() <= 1:
						tl.diags.append(GDiag.make(op.line, 0, 0, GDiag.Severity.WARNING,
							"Коду ожидания %s нет пары в других каналах" % op.wait_tag, id))
						cursor[id] += 1
						progressed = true
						continue
					blocked[id] = {"tag": op.wait_tag, "since": clock[id], "line": op.line}
					break
				var start: float = clock[id]
				var slot := GSlot.make(op, start, start + op.duration)
				tl.items.append(slot)
				tl.by_channel[id].append(slot)
				clock[id] = slot.end
				cursor[id] += 1
				progressed = true

		var released := _release_barriers(ids, ops_by_channel, participants, cursor, clock, blocked, tl)

		var all_done := true
		for id in ids:
			if cursor[id] < (ops_by_channel[id] as Array).size() or blocked[id] != null:
				all_done = false
				break
		if all_done:
			break
		if not progressed and not released:
			for id in ids:
				var b = blocked[id]
				if b != null:
					tl.diags.append(GDiag.make(b["line"], 0, 0, GDiag.Severity.ERROR,
						"Взаимная блокировка: канал ждёт %s, а парный канал туда не приходит" % b["tag"], id))
			break

	tl.items.sort_custom(func(a: GSlot, b: GSlot) -> bool: return a.start < b.start)
	var total := 0.0
	for id in ids:
		total = maxf(total, clock[id])
	tl.total_time = total
	return tl


static func _release_barriers(ids: Array[String], ops_by_channel: Dictionary, participants: Dictionary,
		cursor: Dictionary, clock: Dictionary, blocked: Dictionary, tl: GTimeline) -> bool:
	var tags := {}
	for id in ids:
		var b = blocked[id]
		if b != null:
			tags[b["tag"]] = true

	var released := false
	for tag in tags.keys():
		var need: Dictionary = participants[tag]
		var arrived: Array[String] = []
		for id in ids:
			var b = blocked[id]
			if b != null and b["tag"] == tag:
				arrived.append(id)

		var all_here := true
		for id in need.keys():
			var finished: bool = cursor[id] >= (ops_by_channel[id] as Array).size()
			if not arrived.has(id) and not finished:
				all_here = false
				break
		if not all_here:
			continue

		var release_at := 0.0
		for id in arrived:
			release_at = maxf(release_at, blocked[id]["since"])
		for id in arrived:
			var b = blocked[id]
			if release_at > b["since"]:
				var span := GWaitSpan.new()
				span.channel = id
				span.tag = tag
				span.from_time = b["since"]
				span.to_time = release_at
				span.line = b["line"]
				tl.waits.append(span)
			clock[id] = release_at
			cursor[id] += 1
			blocked[id] = null
		released = true
	return released
