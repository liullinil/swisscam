class_name Simulation
extends RefCounted

## Прогон программы по заготовке с возможностью перемотки в любой кадр.
##
## Симуляция считается один раз целиком: попутно собирается статистика по кадрам
## и опорные снимки заготовки, чтобы ползунок времени работал мгновенно.

const SNAPSHOT_EVERY := 96

var settings: SimSettings
var stock: StockProfile
var items: Array[GSlot] = []
## По одному словарю на кадр: {volume, mrr, modelled}
var steps: Array = []
var _snapshots: Array = []
var _cursor := 0
## Плоскость отрезки, найденная за полный прогон. NAN — деталь не отрезана.
var final_cutoff_z := NAN
## Итоги полного прогона: их не сбрасывает перемотка в начало.
var total_removed := 0.0
var final_volume := 0.0


static func create(timeline: GTimeline, p_settings: SimSettings) -> Simulation:
	var sim := Simulation.new()
	sim.settings = p_settings
	sim.items = timeline.items
	sim.stock = StockProfile.create(p_settings.bar_diameter, p_settings.z_min, p_settings.z_max, p_settings.grid_step)
	sim._snap()
	sim._run_all()
	sim.rewind()
	return sim


func _snap() -> void:
	_snapshots.append({
		"index": _cursor,
		"field": stock.snapshot(),
		"removed": stock.removed,
		"cutoff": stock.cutoff_z,
	})


func _restore(s: Dictionary) -> void:
	stock.restore(s["field"], s["removed"], s["cutoff"])
	_cursor = s["index"]


func _run_all() -> void:
	steps.resize(items.size())
	while _cursor < items.size():
		steps[_cursor] = _apply(items[_cursor])
		_cursor += 1
		if _cursor % SNAPSHOT_EVERY == 0:
			_snap()
	final_cutoff_z = stock.cutoff_z
	total_removed = stock.removed
	final_volume = stock.volume()


func rewind() -> void:
	_restore(_snapshots[0])


## Приводит модель к состоянию после кадра index включительно.
func seek(index: int) -> void:
	var target := clampi(index, -1, items.size() - 1)
	var best: Dictionary = _snapshots[0]
	for s in _snapshots:
		if s["index"] <= target + 1 and s["index"] >= best["index"]:
			best = s
	if _cursor > target + 1 or _cursor < best["index"]:
		_restore(best)
	while _cursor <= target:
		_apply(items[_cursor])
		_cursor += 1


func cursor() -> int:
	return _cursor


func _apply(slot: GSlot) -> Dictionary:
	var info := {"volume": 0.0, "mrr": 0.0, "modelled": false}
	var op := slot.op
	if op.kind != GOp.Kind.MOVE or op.move == GOp.Move.RAPID:
		return info

	var tool := settings.tools.get_tool(op.tool)
	if not tool.cuts_material():
		return info

	var z0 := op.from_pos.z
	var z1 := op.to_pos.z
	if settings.sub_mirror and op.sub_spindle:
		var plane: float = settings.cut_plane if is_nan(stock.cutoff_z) else stock.cutoff_z
		z0 = plane - z0
		z1 = plane - z1

	# Радиус знаковый: сторона подхода инструмента важна, а проход за центр — отрезка
	var r0 := op.from_pos.x * 0.5
	var r1 := op.to_pos.x * 0.5

	var vol := 0.0
	if tool.kind == ToolDef.Kind.DRILL:
		vol = stock.bore(z0, z1, tool.diameter * 0.5)
	else:
		vol = stock.turn(z0, r0, z1, r1, tool.width)

	info["volume"] = vol
	info["modelled"] = true
	var dt := slot.end - slot.start
	info["mrr"] = vol / dt * 60.0 if dt > 0.0 else 0.0
	return info
