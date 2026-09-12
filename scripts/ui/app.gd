extends Control

## Главное окно: редактор программы слева, заготовка и время цикла справа.
##
## Интерфейс собирается кодом, а не сценой: панелей немного, зато всё, что
## показывается технологу, видно в одном файле рядом с логикой обновления.

const SAMPLE_MAIN := "res://samples/hanwha_main.nc"
const SAMPLE_SUB := "res://samples/hanwha_sub.nc"
const REBUILD_DELAY := 0.45

var job: GJob
var dialect: GDialect = GDialect.hanwha()
## id канала -> {name, text}
var sources := {}
var current_channel := "1"

var playing := false
var play_speed := 5.0
var sim_time := 0.0
var _last_index := -1
var _highlighted_lines := {}
var _bar_override := 0.0

var code_edit: CodeEdit
var channel_tabs: TabBar
var stock_view: StockView
var gantt: GanttView
var diag_list: ItemList
var tool_list: ItemList
var section_list: ItemList
var stats_label: RichTextLabel
var guess_label: Label
var scrub: HSlider
var clock_label: Label
var play_button: Button
var bar_spin: SpinBox
var dialect_option: OptionButton
var file_dialog: FileDialog
var rebuild_timer: Timer
var _suppress_text_signal := false


## Съёмка окна для проверки вида без запуска руками:
## Godot --path . -- --shot=out.png --at=0.55 --frames=60
var _shot_path := ""
var _shot_frames := 0


func _ready() -> void:
	_build_ui()
	_load_samples()
	_rebuild()
	_setup_screenshot()


func _setup_screenshot() -> void:
	var at := 0.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			_shot_frames = int(a.substr(9))
		elif a.begins_with("--at="):
			at = a.substr(5).to_float()
	if _shot_path.is_empty():
		return
	if _shot_frames <= 0:
		_shot_frames = 45
	if job != null:
		_on_seek_time(job.timeline.total_time * clampf(at, 0.0, 1.0))


# --- построение интерфейса ---

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_toolbar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 520
	root.add_child(split)

	split.add_child(_build_editor_pane())
	split.add_child(_build_view_pane())

	root.add_child(_build_status_bar())

	rebuild_timer = Timer.new()
	rebuild_timer.one_shot = true
	rebuild_timer.wait_time = REBUILD_DELAY
	rebuild_timer.timeout.connect(_rebuild)
	add_child(rebuild_timer)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.nc, *.txt, *.cnc, *.prg, *.mpf ; Управляющие программы", "* ; Все файлы"])
	file_dialog.files_selected.connect(_on_files_chosen)
	file_dialog.file_selected.connect(func(p: String) -> void: _on_files_chosen(PackedStringArray([p])))
	add_child(file_dialog)


func _build_toolbar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_style(Color("1b1f26"), Color("2e3541")))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	panel.add_child(bar)

	var brand := Label.new()
	brand.text = "SwissCAM"
	brand.add_theme_color_override("font_color", Color("f0a020"))
	bar.add_child(brand)

	bar.add_child(_label("Стойка"))
	dialect_option = OptionButton.new()
	for d in GDialect.presets():
		dialect_option.add_item(d.title)
	dialect_option.item_selected.connect(_on_dialect_selected)
	bar.add_child(dialect_option)

	bar.add_child(_label("Пруток Ø"))
	bar_spin = SpinBox.new()
	bar_spin.min_value = 1.0
	bar_spin.max_value = 120.0
	bar_spin.step = 0.5
	bar_spin.value = 26.0
	bar_spin.custom_minimum_size.x = 90.0
	bar_spin.value_changed.connect(_on_bar_changed)
	bar.add_child(bar_spin)

	var open_btn := Button.new()
	open_btn.text = "Открыть…"
	open_btn.pressed.connect(_on_open_pressed)
	bar.add_child(open_btn)

	var sample_btn := Button.new()
	sample_btn.text = "Эталон Hanwha"
	sample_btn.pressed.connect(func() -> void:
		_load_samples()
		_rebuild())
	bar.add_child(sample_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	guess_label = Label.new()
	guess_label.clip_text = true
	guess_label.custom_minimum_size.x = 260.0
	guess_label.add_theme_color_override("font_color", Color("8d97a8"))
	bar.add_child(guess_label)
	return panel


func _build_editor_pane() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size.x = 340.0

	channel_tabs = TabBar.new()
	channel_tabs.tab_changed.connect(_on_channel_changed)
	box.add_child(channel_tabs)

	code_edit = CodeEdit.new()
	code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code_edit.gutters_draw_line_numbers = true
	code_edit.syntax_highlighter = GCodeHighlighter.new()
	code_edit.add_theme_color_override("background_color", Color("14171c"))
	code_edit.add_theme_font_size_override("font_size", 13)
	code_edit.text_changed.connect(_on_text_changed)
	box.add_child(code_edit)
	return box


func _build_view_pane() -> Control:
	var split := VSplitContainer.new()
	split.split_offset = 380

	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.custom_minimum_size.y = 220.0
	viewport_container.gui_input.connect(_on_view_input)
	var sub := SubViewport.new()
	sub.handle_input_locally = false
	sub.gui_disable_input = true
	sub.msaa_3d = Viewport.MSAA_4X
	sub.transparent_bg = false
	viewport_container.add_child(sub)
	stock_view = StockView.new()
	sub.add_child(stock_view)
	split.add_child(viewport_container)

	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 0)
	bottom.custom_minimum_size.y = 200.0
	bottom.add_child(_build_transport())

	gantt = GanttView.new()
	gantt.custom_minimum_size.y = 96.0
	gantt.seek_requested.connect(_on_seek_time)
	bottom.add_child(gantt)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size.y = 110.0

	diag_list = ItemList.new()
	diag_list.name = "Замечания"
	diag_list.item_selected.connect(_on_diag_selected)
	tabs.add_child(diag_list)

	tool_list = ItemList.new()
	tool_list.name = "Инструмент"
	tabs.add_child(tool_list)

	section_list = ItemList.new()
	section_list.name = "Разделы"
	section_list.item_selected.connect(_on_section_selected)
	tabs.add_child(section_list)

	bottom.add_child(tabs)
	split.add_child(bottom)
	return split


func _build_transport() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_style(Color("1b1f26"), Color("2e3541")))
	var bar := HBoxContainer.new()
	panel.add_child(bar)

	play_button = Button.new()
	play_button.text = "Пуск"
	play_button.tooltip_text = "Пуск и пауза (пробел)"
	play_button.pressed.connect(_toggle_play)
	bar.add_child(play_button)

	var reset := Button.new()
	reset.text = "|<"
	reset.tooltip_text = "В начало"
	reset.pressed.connect(func() -> void: _on_seek_time(0.0))
	bar.add_child(reset)

	var to_end := Button.new()
	to_end.text = ">|"
	to_end.tooltip_text = "В конец"
	to_end.pressed.connect(func() -> void:
		if job != null:
			_on_seek_time(job.timeline.total_time))
	bar.add_child(to_end)

	scrub = HSlider.new()
	scrub.min_value = 0.0
	scrub.max_value = 1.0
	scrub.step = 0.0001
	scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrub.value_changed.connect(_on_scrub)
	bar.add_child(scrub)

	var speed := OptionButton.new()
	for s in [1.0, 5.0, 20.0, 100.0]:
		speed.add_item("×%d" % int(s))
	speed.selected = 1
	speed.item_selected.connect(func(i: int) -> void: play_speed = [1.0, 5.0, 20.0, 100.0][i])
	bar.add_child(speed)

	clock_label = Label.new()
	clock_label.custom_minimum_size.x = 110.0
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(clock_label)

	var rapid_check := CheckBox.new()
	rapid_check.text = "холостые"
	rapid_check.toggled.connect(func(on: bool) -> void: stock_view.set_show_rapid(on))
	bar.add_child(rapid_check)

	var path_check := CheckBox.new()
	path_check.text = "траектории"
	path_check.button_pressed = true
	path_check.toggled.connect(func(on: bool) -> void: stock_view.set_show_paths(on))
	bar.add_child(path_check)

	var section_check := CheckBox.new()
	section_check.text = "разрез"
	section_check.toggled.connect(func(on: bool) -> void: stock_view.set_section(on))
	bar.add_child(section_check)

	var fit := Button.new()
	fit.text = "Вписать"
	fit.pressed.connect(func() -> void: stock_view.frame_all())
	bar.add_child(fit)
	return panel


func _build_status_bar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_style(Color("1b1f26"), Color("2e3541")))
	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.custom_minimum_size.y = 22.0
	stats_label.scroll_active = false
	panel.add_child(stats_label)
	return panel


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("8d97a8"))
	return l


func _flat_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_bottom = 1
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


# --- загрузка программ ---

func _load_samples() -> void:
	sources.clear()
	sources["1"] = {"name": "hanwha_main.nc", "text": _read(SAMPLE_MAIN)}
	sources["2"] = {"name": "hanwha_sub.nc", "text": _read(SAMPLE_SUB)}
	current_channel = "1"


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _on_open_pressed() -> void:
	if OS.has_feature("web"):
		WebFiles.pick_text_files(_on_web_files)
		return
	file_dialog.popup_centered_ratio(0.7)


func _on_files_chosen(paths: PackedStringArray) -> void:
	var loaded := []
	for p in paths:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		loaded.append({"name": p.get_file(), "text": f.get_as_text()})
	_accept_loaded(loaded)


func _on_web_files(loaded: Array) -> void:
	_accept_loaded(loaded)


## Раскладывает выбранные файлы по каналам: первый — главный шпиндель,
## второй — противошпиндель. Имя файла с «sub» или «2» уточняет порядок.
func _accept_loaded(loaded: Array) -> void:
	if loaded.is_empty():
		return
	sources.clear()
	var ids := ["1", "2", "3", "4"]
	loaded.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _channel_hint(a["name"]) < _channel_hint(b["name"]))
	for i in loaded.size():
		if i >= ids.size():
			break
		sources[ids[i]] = loaded[i]
	current_channel = "1"
	_rebuild()


static func _channel_hint(name: String) -> int:
	var n := name.to_lower()
	if n.contains("sub") or n.contains("back") or n.contains("_2") or n.contains("прот"):
		return 2
	return 1


# --- пересчёт ---

func _rebuild() -> void:
	var srcs := []
	var ids := sources.keys()
	ids.sort()
	for id in ids:
		srcs.append({"id": id, "name": sources[id]["name"], "text": sources[id]["text"]})
	if srcs.is_empty():
		return

	job = GJob.build(srcs, dialect, null)
	# Диаметр прутка, введённый руками, важнее догадки по программе
	if _bar_override > 0.0 and not is_equal_approx(_bar_override, job.settings.bar_diameter):
		job.settings.bar_diameter = _bar_override
		job.sim = Simulation.create(job.timeline, job.settings)

	_refresh_tabs()
	_refresh_editor()
	_refresh_lists()
	stock_view.set_job(job)
	gantt.set_timeline(job.timeline)
	scrub.max_value = maxf(job.timeline.total_time, 0.001)
	_suppress_text_signal = true
	bar_spin.value = job.settings.bar_diameter
	_suppress_text_signal = false
	guess_label.text = "   ".join(job.settings.guesses)
	_last_index = -1
	_on_seek_time(0.0)
	_refresh_stats()


func _refresh_tabs() -> void:
	channel_tabs.clear_tabs()
	var ids := sources.keys()
	ids.sort()
	for id in ids:
		channel_tabs.add_tab("$%s  %s" % [id, sources[id]["name"]])
	var idx := ids.find(current_channel)
	if idx >= 0:
		channel_tabs.current_tab = idx


func _refresh_editor() -> void:
	if not sources.has(current_channel):
		return
	_suppress_text_signal = true
	var caret := code_edit.get_caret_line()
	code_edit.text = sources[current_channel]["text"]
	code_edit.set_caret_line(mini(caret, maxi(code_edit.get_line_count() - 1, 0)))
	_suppress_text_signal = false


func _refresh_lists() -> void:
	diag_list.clear()
	var shown := 0
	for d: GDiag in job.diags:
		if shown >= 400:
			break
		shown += 1
		var idx := diag_list.add_item("строка %d  ·  %s%s" % [
			d.line + 1, d.message, "" if d.channel.is_empty() else "   [$%s]" % d.channel])
		diag_list.set_item_custom_fg_color(idx, d.color())
		diag_list.set_item_metadata(idx, {"line": d.line, "channel": d.channel})

	tool_list.clear()
	for id in job.tools.ids_sorted():
		var t: ToolDef = job.tools.tools[id]
		var extra := ""
		if t.kind == ToolDef.Kind.DRILL:
			extra = "   Ø%.1f" % t.diameter
		elif t.width > 0.0:
			extra = "   ширина %.1f" % t.width
		if t.nose_r > 0.0:
			extra += "   r%.2f" % t.nose_r
		if not t.from_header:
			extra += "   (определён по движениям)"
		tool_list.add_item(t.describe() + extra)

	section_list.clear()
	for ch in job.channels:
		for s in ch.sections():
			var idx := section_list.add_item("$%s  %s" % [ch.id, s["name"]])
			section_list.set_item_metadata(idx, {"line": s["line"], "channel": ch.id})


func _refresh_stats() -> void:
	if job == null:
		return
	var s := job.summary()
	var parts := PackedStringArray()
	parts.append("Время цикла [b]%s[/b]" % GanttView._fmt_time(s["total"]))
	parts.append("резание %s" % GanttView._fmt_time(s["cutting"]))
	parts.append("холостые %s" % GanttView._fmt_time(s["rapid"]))
	parts.append("ожидание [color=#ff6b6b]%s[/color]" % GanttView._fmt_time(s["waiting"]))
	parts.append("снято %.0f мм3" % job.sim.total_removed)
	if not is_nan(job.sim.final_cutoff_z):
		parts.append("отрезка Z%.2f" % job.sim.final_cutoff_z)
	parts.append("замечаний: %d / %d" % [job.error_count(), job.warning_count()])
	stats_label.text = "    ".join(parts)


# --- обработка событий ---

func _on_text_changed() -> void:
	if _suppress_text_signal:
		return
	if sources.has(current_channel):
		sources[current_channel]["text"] = code_edit.text
	rebuild_timer.start()


func _on_channel_changed(tab: int) -> void:
	var ids := sources.keys()
	ids.sort()
	if tab < 0 or tab >= ids.size():
		return
	current_channel = ids[tab]
	_refresh_editor()


func _on_dialect_selected(index: int) -> void:
	dialect = GDialect.presets()[index]
	_rebuild()


func _on_bar_changed(value: float) -> void:
	if _suppress_text_signal or job == null:
		return
	if is_equal_approx(value, job.settings.bar_diameter):
		return
	_bar_override = value
	job.settings.bar_diameter = value
	job.sim = Simulation.create(job.timeline, job.settings)
	stock_view.set_job(job)
	_on_seek_time(sim_time)
	_refresh_stats()


func _on_diag_selected(index: int) -> void:
	var meta = diag_list.get_item_metadata(index)
	if meta == null:
		return
	_go_to(meta["channel"], meta["line"])


func _on_section_selected(index: int) -> void:
	var meta = section_list.get_item_metadata(index)
	if meta == null:
		return
	_go_to(meta["channel"], meta["line"])


func _go_to(channel: String, line: int) -> void:
	if not channel.is_empty() and sources.has(channel) and channel != current_channel:
		current_channel = channel
		_refresh_tabs()
		_refresh_editor()
	code_edit.set_caret_line(line)
	code_edit.center_viewport_to_caret()
	code_edit.grab_focus()


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			stock_view.orbit(event.relative)
		elif (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0 or (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			stock_view.pan(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			stock_view.zoom(1.0 / 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			stock_view.zoom(1.12)


func _on_scrub(value: float) -> void:
	if is_equal_approx(value, sim_time):
		return
	_apply_time(value)


func _on_seek_time(t: float) -> void:
	_apply_time(t)
	scrub.set_value_no_signal(t)


func _toggle_play() -> void:
	playing = not playing
	play_button.text = "Пауза" if playing else "Пуск"
	if playing and job != null and sim_time >= job.timeline.total_time - 0.001:
		_apply_time(0.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE and not code_edit.has_focus():
		_toggle_play()
		accept_event()


func _process(delta: float) -> void:
	if not _shot_path.is_empty():
		_shot_frames -= 1
		if _shot_frames <= 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(_shot_path)
			print("снимок: ", _shot_path)
			get_tree().quit()
		return
	if not playing or job == null:
		return
	var t := sim_time + delta * play_speed
	if t >= job.timeline.total_time:
		t = job.timeline.total_time
		playing = false
		play_button.text = "Пуск"
	_on_seek_time(t)


func _apply_time(t: float) -> void:
	if job == null:
		return
	sim_time = clampf(t, 0.0, job.timeline.total_time)
	var index := job.timeline.index_at_time(sim_time)
	if index != _last_index:
		job.sim.seek(index)
		stock_view.refresh_profile()
		_last_index = index
	gantt.set_time(sim_time)
	clock_label.text = "%s / %s" % [GanttView._fmt_time(sim_time), GanttView._fmt_time(job.timeline.total_time)]
	_update_markers()
	_highlight_current_lines()


## Ставит указатели каналов туда, где инструмент находится в этот момент.
func _update_markers() -> void:
	for ch in job.channels:
		var slots: Array = job.timeline.by_channel[ch.id]
		var found: GSlot = null
		for slot: GSlot in slots:
			if slot.start > sim_time:
				break
			found = slot
		if found == null or found.op.kind != GOp.Kind.MOVE:
			var last_move := _last_move_before(slots, sim_time)
			if last_move == null:
				stock_view.set_marker(ch.id, 0.0, 0.0, false)
				continue
			found = last_move
		var op := found.op
		var t := 0.0
		if found.end > found.start:
			t = clampf((sim_time - found.start) / (found.end - found.start), 0.0, 1.0)
		var z: float = lerpf(op.from_pos.z, op.to_pos.z, t)
		var r: float = lerpf(op.from_pos.x, op.to_pos.x, t) * 0.5
		stock_view.set_marker(ch.id, z, r, true)


func _last_move_before(slots: Array, t: float) -> GSlot:
	var found: GSlot = null
	for slot: GSlot in slots:
		if slot.start > t:
			break
		if slot.op.kind == GOp.Kind.MOVE:
			found = slot
	return found


func _highlight_current_lines() -> void:
	for line in _highlighted_lines.keys():
		if line < code_edit.get_line_count():
			code_edit.set_line_background_color(line, Color(0, 0, 0, 0))
	_highlighted_lines.clear()
	if not sources.has(current_channel):
		return
	var slots: Array = job.timeline.by_channel.get(current_channel, [])
	var slot := _last_move_before(slots, sim_time)
	if slot == null:
		return
	var line: int = slot.op.line
	if line < code_edit.get_line_count():
		code_edit.set_line_background_color(line, Color(0.94, 0.63, 0.13, 0.16))
		_highlighted_lines[line] = true
