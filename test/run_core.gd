extends SceneTree

## Прогон ядра без графики: godot --headless --script res://test/run_core.gd
##
## Печатает разбор эталонных программ Hanwha — по нему видно, не поехало ли
## что-то в интерпретаторе после правок.

func _initialize() -> void:
	var main_text := _read("res://samples/hanwha_main.nc")
	var sub_text := _read("res://samples/hanwha_sub.nc")
	if main_text.is_empty() or sub_text.is_empty():
		printerr("Не найдены эталонные программы в samples/")
		quit(1)
		return

	var t0 := Time.get_ticks_msec()
	var job := GJob.build([
		{"id": "1", "name": "hanwha_main.nc", "text": main_text},
		{"id": "2", "name": "hanwha_sub.nc", "text": sub_text},
	], GDialect.hanwha())
	var elapsed := Time.get_ticks_msec() - t0

	print("=== SwissCAM: прогон ядра ===")
	print("разбор и симуляция: %d мс" % elapsed)
	print("")

	for ch in job.channels:
		var ops: Array = job.ops_by_channel[ch.id]
		var sections := ch.sections()
		print("%s  (%s)" % [ch.title, ch.source_name])
		print("  кадров: %d, действий: %d, разделов: %d" % [ch.blocks.size(), ops.size(), sections.size()])
		var names := PackedStringArray()
		for s in sections:
			names.append(s["name"])
		if names.size() > 0:
			print("  разделы: " + ", ".join(names))

	print("")
	print("--- инструмент ---")
	for id in job.tools.ids_sorted():
		var t: ToolDef = job.tools.tools[id]
		var extra := ""
		if t.kind == ToolDef.Kind.DRILL:
			extra = "  ⌀%.1f" % t.diameter
		elif t.width > 0.0:
			extra = "  b=%.1f" % t.width
		if t.nose_r > 0.0:
			extra += "  r=%.2f" % t.nose_r
		print("  %s%s%s" % [t.describe(), extra, "" if t.from_header else "  (догадка)"])

	print("")
	print("--- заготовка ---")
	var s := job.settings
	print("  пруток ⌀%.2f, Z от %.1f до %.1f, шаг сетки %.3f мм" % [s.bar_diameter, s.z_min, s.z_max, s.grid_step])
	for g in s.guesses:
		print("  догадка: " + g)

	print("")
	print("--- время цикла ---")
	var sum := job.summary()
	print("  всего: %s" % _hms(sum["total"]))
	print("  суммарно по каналам — резание: %s, холостые: %s, смена инструмента: %s, выдержки: %s" % [
		_hms(sum["cutting"]), _hms(sum["rapid"]), _hms(sum["tool_change"]), _hms(sum["dwell"])])
	print("  простой на ожидании: %s" % _hms(sum["waiting"]))
	for ch in job.channels:
		print("    %s ждёт %s" % [ch.title, _hms(job.timeline.wait_time(ch.id))])

	print("")
	print("--- съём материала ---")
	print("  снято %.0f мм³, осталось %.0f мм³" % [job.sim.total_removed, job.sim.final_volume])
	if is_nan(job.sim.final_cutoff_z):
		print("  деталь не отрезана")
	else:
		print("  отрезка на Z%.3f" % job.sim.final_cutoff_z)

	print("")
	print("--- профиль готовой детали ---")
	job.sim.seek(job.sim.items.size() - 1)
	var probe := [0.0, 15.0, 25.0, 31.0, 35.0, 40.0, 50.0, 55.0, 70.0, 90.0, 95.0, 96.0, 100.0]
	var line := PackedStringArray()
	for z in probe:
		var i: int = job.sim.stock.index_of(z)
		if i < 0 or i >= job.sim.stock.samples:
			continue
		var ro: float = job.sim.stock.outer(i)
		var ri: float = job.sim.stock.inner(i)
		var hole := "" if ri <= 0.001 else "/отв⌀%.1f" % (ri * 2.0)
		line.append("Z%.0f:⌀%.2f%s" % [z, ro * 2.0, hole])
	print("  " + "  ".join(line))

	print("")
	print("--- замечания: %d ошибок, %d предупреждений ---" % [job.error_count(), job.warning_count()])
	var shown := 0
	var seen := {}
	for d in job.diags:
		var key := d.message.left(60)
		if seen.has(key):
			seen[key] += 1
			continue
		seen[key] = 1
		if shown < 12:
			print("  [%s] строка %d: %s" % [d.severity_name(), d.line + 1, d.message])
			shown += 1
	var repeats := 0
	for k in seen.keys():
		if seen[k] > 1:
			repeats += 1
	if repeats > 0:
		print("  (повторяющихся видов замечаний: %d)" % repeats)

	quit(0 if job.error_count() == 0 else 1)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func _hms(seconds: float) -> String:
	if seconds < 60.0:
		return "%.2f с" % seconds
	return "%d:%05.2f" % [int(seconds / 60.0), fmod(seconds, 60.0)]
