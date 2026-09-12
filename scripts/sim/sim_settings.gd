class_name SimSettings
extends RefCounted

## Настройки заготовки и симуляции. То, чего в программе нет, выводится из неё же
## и показывается технологу как догадка, которую можно поправить.

var bar_diameter := 26.0
var z_min := -5.0
var z_max := 105.0
var grid_step := 0.02
## Свободный торец прутка со стороны меньших Z.
var free_end_low := true
var tools: ToolTable = ToolTable.new()
## Пересчитывать координаты противошпинделя зеркально. Постпроцессоры, печатающие
## оба канала в общей системе детали, в этом не нуждаются.
var sub_mirror := false
var cut_plane := 0.0
## Что именно мы угадали — показывается в интерфейсе.
var guesses: PackedStringArray = PackedStringArray()

## Насколько заготовка выступает за крайний рез со стороны свободного торца, мм.
const FACE_MARGIN := 0.2


## Выводит границы заготовки и диаметр прутка из самой программы.
static func from_ops(ops_by_channel: Dictionary, tools_table: ToolTable) -> SimSettings:
	var s := SimSettings.new()
	s.tools = tools_table

	var cut_z_lo := INF
	var cut_z_hi := -INF
	var cut_max_x := 0.0
	var first_feed_z := NAN

	for id in ops_by_channel.keys():
		for op: GOp in ops_by_channel[id]:
			if op.kind != GOp.Kind.MOVE or op.move == GOp.Move.RAPID:
				continue
			if not tools_table.get_tool(op.tool).cuts_material():
				continue
			cut_z_lo = minf(cut_z_lo, minf(op.from_pos.z, op.to_pos.z))
			cut_z_hi = maxf(cut_z_hi, maxf(op.from_pos.z, op.to_pos.z))
			cut_max_x = maxf(cut_max_x, maxf(absf(op.from_pos.x), absf(op.to_pos.x)))
			if is_nan(first_feed_z):
				first_feed_z = op.from_pos.z

	if is_inf(cut_z_lo):
		s.guesses.append("в программе нет рабочих ходов — заготовка взята по умолчанию")
		return s

	# Диаметр прутка: наибольший диаметр реза и подводы рядом с ним.
	# Отводы инструмента вроде X116 в расчёт не берём — они на порядок дальше.
	var bar := cut_max_x
	for id in ops_by_channel.keys():
		for op: GOp in ops_by_channel[id]:
			if op.kind != GOp.Kind.MOVE:
				continue
			var x := maxf(absf(op.from_pos.x), absf(op.to_pos.x))
			if x <= cut_max_x * 1.5:
				bar = maxf(bar, x)
	s.bar_diameter = maxf(snappedf(bar, 0.5), 1.0)
	if s.bar_diameter < bar:
		s.bar_diameter += 0.5
	s.guesses.append("пруток ⌀%.1f — по наибольшему диаметру в программе" % s.bar_diameter)

	# Свободный торец — там, где инструмент впервые входит в материал.
	# С этой стороны заготовка заканчивается сразу за крайним резом,
	# с другой — уходит в цангу, и туда её продлеваем с запасом.
	s.free_end_low = first_feed_z < (cut_z_lo + cut_z_hi) * 0.5
	var tail := maxf((cut_z_hi - cut_z_lo) * 0.05, 2.0)
	if s.free_end_low:
		s.z_min = cut_z_lo - FACE_MARGIN
		s.z_max = cut_z_hi + tail
		s.guesses.append("торец прутка Z%.1f, материал уходит в плюс по Z" % s.z_min)
	else:
		s.z_min = cut_z_lo - tail
		s.z_max = cut_z_hi + FACE_MARGIN
		s.guesses.append("торец прутка Z%.1f, материал уходит в минус по Z" % s.z_max)

	# Сетка: около 5000 отсчётов на длину заготовки, но не мельче 0.01 мм
	s.grid_step = clampf((s.z_max - s.z_min) / 5000.0, 0.01, 0.1)
	return s
