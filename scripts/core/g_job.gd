class_name GJob
extends RefCounted

## Задание: один или несколько файлов УП, разобранных, разложенных по времени
## и прогнанных по заготовке. У Hanwha каналы лежат отдельными файлами, поэтому
## задание — это набор файлов, а не один текст.

var dialect: GDialect = GDialect.hanwha()
var channels: Array[GChannel] = []
var ops_by_channel := {}
var timeline: GTimeline
var tools: ToolTable
var settings: SimSettings
var sim: Simulation
var diags: Array[GDiag] = []
## id канала -> исходный текст, как его показывает редактор.
var sources := {}


## sources_in: массив словарей {id, name, text}.
static func build(sources_in: Array, p_dialect: GDialect, settings_override: SimSettings = null) -> GJob:
	var job := GJob.new()
	job.dialect = p_dialect

	for src in sources_in:
		var id := str(src.get("id", "1"))
		var text := str(src.get("text", ""))
		job.sources[id] = text
		var prog := GLexer.parse_program(text)
		job.diags.append_array(prog.diags)
		# Внутри файла могут быть свои заголовки $n; если их нет, весь файл — один канал
		for ch in prog.channels:
			var target_id := id if prog.channels.size() == 1 else ch.id
			ch.id = target_id
			ch.title = GChannel.default_title(target_id)
			ch.source_name = str(src.get("name", ""))
			job.channels.append(ch)

	job.channels.sort_custom(func(a: GChannel, b: GChannel) -> bool: return a.id < b.id)

	var bar_hint := p_dialect.default_bar_diameter
	if settings_override != null:
		bar_hint = settings_override.bar_diameter
	for ch in job.channels:
		job.ops_by_channel[ch.id] = GInterp.run(ch, p_dialect, bar_hint, job.diags)

	job.tools = ToolTable.build(job.channels, job.ops_by_channel)
	job.timeline = GSched.schedule(job.ops_by_channel)
	job.diags.append_array(job.timeline.diags)

	if settings_override != null:
		job.settings = settings_override
		job.settings.tools = job.tools
	else:
		job.settings = SimSettings.from_ops(job.ops_by_channel, job.tools)
	job.sim = Simulation.create(job.timeline, job.settings)
	return job


func error_count() -> int:
	var n := 0
	for d in diags:
		if d.severity == GDiag.Severity.ERROR:
			n += 1
	return n


func warning_count() -> int:
	var n := 0
	for d in diags:
		if d.severity == GDiag.Severity.WARNING:
			n += 1
	return n


## Сводка по заданию для строки состояния.
func summary() -> Dictionary:
	var cutting := 0.0
	var rapid := 0.0
	var tool_change := 0.0
	var dwell := 0.0
	for slot in timeline.items:
		match slot.op.kind:
			GOp.Kind.MOVE:
				if slot.op.move == GOp.Move.RAPID:
					rapid += slot.op.duration
				else:
					cutting += slot.op.duration
			GOp.Kind.TOOL:
				tool_change += slot.op.duration
			GOp.Kind.DWELL:
				dwell += slot.op.duration
	var waiting := 0.0
	for w in timeline.waits:
		waiting += w.seconds()
	return {
		"total": timeline.total_time,
		"cutting": cutting,
		"rapid": rapid,
		"tool_change": tool_change,
		"dwell": dwell,
		"waiting": waiting,
		"removed": sim.stock.removed if sim != null else 0.0,
		"blocks": _block_count(),
		"channels": channels.size(),
	}


func _block_count() -> int:
	var n := 0
	for ch in channels:
		n += ch.blocks.size()
	return n
