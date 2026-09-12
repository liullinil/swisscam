class_name GanttView
extends Control

## Диаграмма занятости каналов: где резание, где холостые, а где канал просто
## стоит и ждёт парный код. Обычно именно в красных полосах и прячется
## минута на деталь.

signal seek_requested(time: float)

const LABEL_WIDTH := 54.0
const RIGHT_PAD := 10.0
const RULER_HEIGHT := 16.0

var timeline: GTimeline
var time := 0.0
var _row_colors := {
	"1": Color("4ea3ff"),
	"2": Color("37d39a"),
	"3": Color("c47bff"),
}


func set_timeline(p_timeline: GTimeline) -> void:
	timeline = p_timeline
	queue_redraw()


func set_time(p_time: float) -> void:
	time = p_time
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if timeline == null or timeline.total_time <= 0.0:
		return
	var want := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		want = true
		pos = event.position
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		want = true
		pos = event.position
	if not want:
		return
	var usable := size.x - LABEL_WIDTH - RIGHT_PAD
	if usable <= 0.0:
		return
	var t := clampf((pos.x - LABEL_WIDTH) / usable, 0.0, 1.0) * timeline.total_time
	seek_requested.emit(t)
	accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("14171c"))
	if timeline == null or timeline.total_time <= 0.0:
		return

	var font := get_theme_default_font()
	var font_size := 10
	var ids := timeline.channel_ids()
	var usable := size.x - LABEL_WIDTH - RIGHT_PAD
	var rows := maxi(ids.size(), 1)
	var row_h := minf(26.0, (size.y - RULER_HEIGHT - 4.0) / float(rows))

	for row in ids.size():
		var id := ids[row]
		var y := 2.0 + row * row_h
		var h := row_h - 4.0
		draw_string(font, Vector2(6.0, y + h * 0.75), "$" + id, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("8d97a8"))
		draw_rect(Rect2(LABEL_WIDTH, y, usable, h), Color("1b1f26"))

		for slot: GSlot in timeline.by_channel[id]:
			if slot.end <= slot.start:
				continue
			var x0 := _x_of(slot.start, usable)
			var x1 := maxf(_x_of(slot.end, usable), x0 + 1.0)
			draw_rect(Rect2(x0, y, x1 - x0, h), _slot_color(slot, id))

		for w: GWaitSpan in timeline.waits:
			if w.channel != id:
				continue
			var x0 := _x_of(w.from_time, usable)
			var x1 := maxf(_x_of(w.to_time, usable), x0 + 1.0)
			draw_rect(Rect2(x0, y, x1 - x0, h), Color(1.0, 0.42, 0.42, 0.32))
			draw_rect(Rect2(x0, y, x1 - x0, h), Color("ff6b6b"), false, 1.0)

	_draw_ruler(font, font_size, usable)

	var cx := _x_of(time, usable)
	draw_line(Vector2(cx, 0.0), Vector2(cx, size.y - RULER_HEIGHT), Color("f0a020"), 1.5)


func _slot_color(slot: GSlot, id: String) -> Color:
	var op := slot.op
	match op.kind:
		GOp.Kind.MOVE:
			if op.move == GOp.Move.RAPID:
				return Color("434b5a")
			return _row_colors.get(id, Color.WHITE)
		GOp.Kind.TOOL:
			return Color("ffc857")
		GOp.Kind.DWELL:
			return Color("ff9d5c")
		_:
			return Color("5a6473")


func _x_of(t: float, usable: float) -> float:
	return LABEL_WIDTH + t / timeline.total_time * usable


func _draw_ruler(font: Font, font_size: int, usable: float) -> void:
	var steps := [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0]
	var px_per_sec := usable / timeline.total_time
	var step := 60.0
	for s in steps:
		if s * px_per_sec >= 58.0:
			step = s
			break
	var y := size.y - 3.0
	var t := 0.0
	while t <= timeline.total_time:
		var x := _x_of(t, usable)
		draw_line(Vector2(x, size.y - RULER_HEIGHT), Vector2(x, size.y - RULER_HEIGHT + 4.0), Color("39414f"))
		draw_string(font, Vector2(x + 2.0, y), _fmt_time(t), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("636d7d"))
		t += step


static func _fmt_time(t: float) -> String:
	if t < 60.0:
		return "%.1f с" % t
	return "%d:%02d" % [int(t / 60.0), int(fmod(t, 60.0))]
