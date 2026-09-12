class_name ToolTable
extends RefCounted

## Таблица инструмента.
##
## Постпроцессоры печатают список инструмента в шапке программы и повторяют
## описание в кадре смены — этого хватает, чтобы узнать тип, радиус при вершине
## и диаметр сверла, не заставляя технолога заполнять таблицу заново.
## Чего в комментариях нет, угадывается по характеру движений и правится руками.

var tools := {}  ## int -> ToolDef

static var _header_re: RegEx
static var _nose_re: RegEx
static var _mm_re: RegEx
static var _width_re: RegEx


static func _ensure_re() -> void:
	if _header_re == null:
		_header_re = RegEx.create_from_string("(?i)^T0*(\\d+)\\s+(.+)$")
		_nose_re = RegEx.create_from_string("(?i)\\bRe\\s*([0-9]*\\.?[0-9]+)")
		_mm_re = RegEx.create_from_string("(?i)([0-9]*\\.?[0-9]+)\\s*mm")
		_width_re = RegEx.create_from_string("(?i)\\bLa\\s*([0-9]*\\.?[0-9]+)")


static func kind_from_name(name: String) -> ToolDef.Kind:
	var n := name.to_lower()
	if n.contains("gripper") or n.contains("захват") or n.contains("catch"):
		return ToolDef.Kind.GRIPPER
	if n.contains("drill") or n.contains("сверло"):
		return ToolDef.Kind.DRILL
	if n.contains("part-off") or n.contains("part off") or n.contains("cut-off") or n.contains("отрез"):
		return ToolDef.Kind.CUTOFF
	if n.contains("groov") or n.contains("канав"):
		return ToolDef.Kind.GROOVE
	if n.contains("thread") or n.contains("tap") or n.contains("резьб"):
		return ToolDef.Kind.THREAD
	if n.contains("mill") or n.contains("фрез"):
		return ToolDef.Kind.LIVE
	return ToolDef.Kind.TURN


## Заполняет описание инструмента из текста комментария.
static func apply_comment(tool: ToolDef, comment: String) -> void:
	_ensure_re()
	tool.name = comment.strip_edges()
	tool.kind = kind_from_name(comment)
	tool.from_header = true
	var nose := _nose_re.search(comment)
	if nose:
		tool.nose_r = nose.get_string(1).to_float()
	if tool.kind == ToolDef.Kind.DRILL:
		var mm := _mm_re.search(comment)
		if mm:
			tool.diameter = mm.get_string(1).to_float()
	elif tool.kind == ToolDef.Kind.GROOVE or tool.kind == ToolDef.Kind.CUTOFF:
		var w := _width_re.search(comment)
		if w:
			tool.width = w.get_string(1).to_float()
		elif tool.width <= 0.0:
			tool.width = 2.0


## Список инструмента из шапки: строки вида ( T0001    La4 Re0.2 R OD grooving tool ).
func read_header(channels: Array[GChannel]) -> void:
	_ensure_re()
	for ch in channels:
		for b in ch.blocks:
			for c in b.comments:
				var m := _header_re.search(c.strip_edges())
				if m == null:
					continue
				var id := int(m.get_string(1))
				if id <= 0:
					continue
				var t: ToolDef = tools.get(id, ToolDef.make(id))
				apply_comment(t, m.get_string(2))
				tools[id] = t


## Описания из кадров смены инструмента: T0202( IC10 Re0.2 R OD cutting tool ).
func read_tool_comments(channels: Array[GChannel]) -> void:
	for ch in channels:
		for id in ch.tool_comments.keys():
			var comment: String = ch.tool_comments[id]
			if comment.strip_edges().is_empty():
				continue
			var t: ToolDef = tools.get(id, ToolDef.make(id))
			if not t.from_header:
				apply_comment(t, comment)
			tools[id] = t


## Достраивает таблицу по характеру движений: чего нет в комментариях, видно по работе.
func infer_from_motion(ops_by_channel: Dictionary) -> void:
	var stats := {}
	for id in ops_by_channel.keys():
		for op: GOp in ops_by_channel[id]:
			if not op.is_cutting_move():
				continue
			var tid := op.tool
			if tid <= 0:
				continue
			if not stats.has(tid):
				stats[tid] = {"axial": 0.0, "radial": 0.0, "along": 0.0, "min_x": INF}
			var st: Dictionary = stats[tid]
			var dx: float = absf(op.to_pos.x - op.from_pos.x) * 0.5
			var dz: float = absf(op.to_pos.z - op.from_pos.z)
			st["min_x"] = minf(st["min_x"], minf(absf(op.to_pos.x), absf(op.from_pos.x)))
			if dz > dx * 4.0:
				st["along"] += dz
			elif dx > dz * 4.0:
				st["radial"] += dx
			if dz > 0.0 and absf(op.to_pos.x) < 0.05 and absf(op.from_pos.x) < 0.05:
				st["axial"] += dz

	for tid in stats.keys():
		var st: Dictionary = stats[tid]
		var t: ToolDef = tools.get(tid, ToolDef.make(tid))
		if not t.from_header:
			if st["axial"] > 0.5:
				t.kind = ToolDef.Kind.DRILL
			elif st["radial"] > st["along"]:
				t.kind = ToolDef.Kind.CUTOFF if st["min_x"] <= 0.2 else ToolDef.Kind.GROOVE
			else:
				t.kind = ToolDef.Kind.TURN
			var fresh := ToolDef.make(tid, t.kind)
			fresh.name = t.name
			t = fresh
		# Отрезной узнаётся по проходу за центр независимо от описания
		if t.kind == ToolDef.Kind.GROOVE and st["min_x"] <= 0.2:
			t.kind = ToolDef.Kind.CUTOFF
		tools[tid] = t


func get_tool(id: int) -> ToolDef:
	if tools.has(id):
		return tools[id]
	var t := ToolDef.make(id)
	tools[id] = t
	return t


func ids_sorted() -> Array:
	var ids := tools.keys()
	ids.sort()
	return ids


static func build(channels: Array[GChannel], ops_by_channel: Dictionary) -> ToolTable:
	var tt := ToolTable.new()
	tt.read_header(channels)
	tt.read_tool_comments(channels)
	tt.infer_from_motion(ops_by_channel)
	return tt
