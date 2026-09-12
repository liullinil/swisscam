class_name GInterp
extends RefCounted

## Модальный интерпретатор: превращает кадры канала в последовательность действий
## с координатами, оборотами и длительностью.
##
## Координаты считаются в системе детали: X — диаметр (знак показывает, с какой
## стороны подходит инструмент), Z — вдоль прутка. Радиус в модель идёт как |X|/2.

const INCH := 25.4

## Циклы, которые мы распознаём, но пока не разворачиваем в траекторию.
const CANNED := [70, 71, 72, 73, 76, 81, 82, 83, 84, 85, 86, 87, 88, 89]
## Команды стойки Hanwha: подача прутка, направляющая втулка, выброс детали.
## Геометрию детали они не меняют, но кадр целиком относится к ним.
const MACHINE_G := [150, 300, 310, 340]
## Коды, ничего не меняющие в нашей модели и не являющиеся ошибкой.
const HARMLESS_G := [7.1, 9.0, 12.1, 13.1, 17.0, 18.0, 19.0, 40.0, 41.0, 42.0, 64.0, 69.0, 80.0]

var _dialect: GDialect
var _channel: GChannel
var _diags: Array[GDiag]

# Модальное состояние
var _motion := 0
var _inch := false
var _feed_per_rev := true
var _feed := 0.0
var _css := false
var _s_value := 0.0
var _rpm_cap := 10000.0
var _tool := 0
var _absolute := true
var _pos := Vector4.ZERO
var _ops: Array[GOp] = []
## Отвод для цикла G74, мм.
var _peck_retract := 0.0
## Комментарий, встреченный в кадре со сменой инструмента — имя инструмента.
var _tool_comments := {}
## Уже отмеченные подозрительные подачи, чтобы не повторять замечание.
var _feed_reported := {}


static func run(channel: GChannel, dialect: GDialect, bar_diameter: float, diags: Array[GDiag]) -> Array[GOp]:
	var it := GInterp.new()
	it._dialect = dialect
	it._channel = channel
	it._diags = diags
	it._feed_per_rev = dialect.feed_per_rev_default
	it._rpm_cap = dialect.max_rpm
	it._pos = Vector4(bar_diameter, 0.0, 0.0, 0.0)
	it._execute()
	channel.tool_comments = it._tool_comments
	return it._ops


func _push(op: GOp) -> void:
	op.sub_spindle = _channel.is_sub_spindle()
	_ops.append(op)


## Диаметр в текущей точке — для скорости резания.
func _diameter(x: float) -> float:
	return absf(x) if _dialect.diameter_x else absf(x) * 2.0


func _current_rpm(x: float) -> float:
	if not _css:
		return minf(_s_value, _rpm_cap)
	var dia := maxf(_diameter(x), 0.01)
	return minf(_s_value * 1000.0 / (PI * dia), _rpm_cap)


func _warn(b: GBlock, msg: String, sev := GDiag.Severity.WARNING) -> void:
	_diags.append(GDiag.make(b.line, 0, maxi(b.raw.length(), 1), sev, msg, _channel.id))


func _execute() -> void:
	for bi in _channel.blocks.size():
		var b: GBlock = _channel.blocks[bi]
		if b.block_delete:
			continue
		if not b.macro.is_empty():
			_warn(b, "Макрокоманда не исполняется в симуляции", GDiag.Severity.INFO)
			continue
		if b.is_empty_block():
			continue

		var scale := INCH if _inch else 1.0
		var flags := _apply_gcodes(b, scale)
		scale = INCH if _inch else 1.0

		_apply_feed_and_speed(b, scale)
		_apply_tool(b, bi)
		_apply_mcodes(b, bi)

		if not b.sync_tag.is_empty():
			var op := GOp.make(GOp.Kind.WAIT, _channel.id, bi, b.line)
			op.wait_tag = "!" + b.sync_tag
			_push(op)

		if flags["dwell"] > 0.0:
			var op := GOp.make(GOp.Kind.DWELL, _channel.id, bi, b.line)
			op.duration = flags["dwell"]
			op.text = "%.2f с" % flags["dwell"]
			_push(op)

		if flags["machine_cmd"] or flags["ref_return"]:
			continue
		if flags["shift"]:
			_apply_shift(b, scale)
			continue
		if flags["peck"]:
			_emit_peck(b, bi, scale)
			continue
		_emit_motion(b, bi, scale)


## Разбирает G-коды кадра, меняет модальное состояние и возвращает флаги кадра.
func _apply_gcodes(b: GBlock, scale: float) -> Dictionary:
	var flags := {"dwell": 0.0, "ref_return": false, "machine_cmd": false, "shift": false, "peck": false}
	for g in b.all_of("G"):
		var gi := snappedf(g, 0.1)
		if gi == 0.0 or gi == 1.0 or gi == 2.0 or gi == 3.0:
			_motion = int(gi)
		elif gi == 4.0:
			flags["dwell"] = _dwell_seconds(b)
		elif gi == 20.0:
			_inch = true
		elif gi == 21.0:
			_inch = false
		elif gi == 28.0 or gi == 30.0:
			flags["ref_return"] = true
		elif gi == 50.0:
			var s := b.value_of("S")
			if not is_nan(s):
				_rpm_cap = minf(s, _dialect.max_rpm) if s > 0.0 else _dialect.max_rpm
			if _has_axis_word(b):
				flags["shift"] = true
		elif gi == 74.0 or gi == 75.0:
			var r := b.value_of("R")
			if not is_nan(r) and is_nan(b.value_of("Z")) and is_nan(b.value_of("X")):
				_peck_retract = r * scale
			else:
				flags["peck"] = true
		elif gi == 94.0 or gi == 98.0:
			_feed_per_rev = false
		elif gi == 95.0 or gi == 99.0:
			_feed_per_rev = true
		elif gi == 96.0:
			_css = true
		elif gi == 97.0:
			_css = false
		elif gi >= 54.0 and gi <= 59.0:
			pass
		elif gi == 90.0:
			_absolute = true
		elif gi == 91.0:
			_absolute = false
		elif gi == 32.0 or gi == 33.0:
			_motion = 32
		elif HARMLESS_G.has(gi):
			pass
		elif MACHINE_G.has(int(gi)):
			flags["machine_cmd"] = true
			_warn(b, "G%s — команда стойки (подача прутка, втулка, выброс): на модель детали не влияет"
				% _fmt(gi), GDiag.Severity.INFO)
		elif CANNED.has(int(gi)):
			_warn(b, "Цикл G%s распознан, но пока не моделируется — траектория не учтена" % _fmt(gi))
		else:
			_warn(b, "Неизвестный код G%s" % _fmt(gi))
	return flags


func _dwell_seconds(b: GBlock) -> float:
	var p := b.value_of("P")
	if not is_nan(p):
		# P на стойках FANUC задаётся в миллисекундах
		return p / 1000.0
	var x := b.value_of("X")
	if is_nan(x):
		x = b.value_of("U")
	return x if not is_nan(x) else 0.0


func _has_axis_word(b: GBlock) -> bool:
	for letter in ["X", "Z", "U", "W", "Y", "V"]:
		if not is_nan(b.value_of(letter)):
			return true
	return false


func _apply_feed_and_speed(b: GBlock, scale: float) -> void:
	var f := b.value_of("F")
	if not is_nan(f):
		_feed = f * scale
		_check_feed(b)
	var s := b.value_of("S")
	if not is_nan(s) and not b.all_of("G").has(50.0):
		_s_value = s


## Подача мимо режима — самая частая опечатка постпроцессора: 200 мм/об вместо
## 200 мм/мин станок отработает буквально.
func _check_feed(b: GBlock) -> void:
	if _feed <= 0.0:
		return
	var key := "%s|%.4f" % ["rev" if _feed_per_rev else "min", _feed]
	if _feed_reported.has(key):
		return
	_feed_reported[key] = true
	if _feed_per_rev and _feed > 5.0:
		_warn(b, "Подача F%.3f мм/об при G99 — похоже на подачу в мм/мин, проверьте G98/G99" % _feed)
	elif not _feed_per_rev and _feed < 2.0:
		_warn(b, "Подача F%.3f мм/мин при G98 — похоже на подачу в мм/об, проверьте G98/G99" % _feed)


func _apply_tool(b: GBlock, bi: int) -> void:
	var t := b.value_of("T")
	if is_nan(t):
		return
	var t_int := int(absf(t))
	@warning_ignore("integer_division")
	var tool_no := t_int / 100 if t_int >= 100 else t_int
	if not b.comments.is_empty() and tool_no > 0:
		_tool_comments[tool_no] = b.comments[0]
	if tool_no == _tool:
		return
	_tool = tool_no
	var op := GOp.make(GOp.Kind.TOOL, _channel.id, bi, b.line)
	op.duration = _dialect.tool_change_time
	op.tool = tool_no
	op.text = "T%04d" % t_int
	_push(op)


func _apply_mcodes(b: GBlock, bi: int) -> void:
	for mc in b.all_of("M"):
		var code := int(mc)
		var op := GOp.make(GOp.Kind.MISC, _channel.id, bi, b.line)
		op.text = "M%d" % code
		if _dialect.is_wait_code(code):
			op.kind = GOp.Kind.WAIT
			op.wait_tag = "M%d" % code
		elif _dialect.cutoff_m.has(code):
			op.kind = GOp.Kind.CUTOFF
		elif code == 2 or code == 30 or code == 99:
			op.kind = GOp.Kind.END
		_push(op)


## G50 со словами осей сдвигает систему координат: текущая точка получает
## новое значение. На станке продольного точения этим возвращают отсчёт Z
## после вытягивания прутка, поэтому координаты детали остаются сквозными.
func _apply_shift(b: GBlock, scale: float) -> void:
	var x := b.value_of("X")
	var z := b.value_of("Z")
	var u := b.value_of("U")
	var w := b.value_of("W")
	if not is_nan(x):
		_pos.x = x * scale
	if not is_nan(z):
		_pos.z = z * scale
	if not is_nan(u):
		_pos.x += u * scale
	if not is_nan(w):
		_pos.z += w * scale


## Цикл G74: сверление с выводом стружки вдоль Z (или прорезка вдоль X при G75).
func _emit_peck(b: GBlock, bi: int, scale: float) -> void:
	var z := b.value_of("Z")
	var x := b.value_of("X")
	var f := b.value_of("F")
	if not is_nan(f):
		_feed = f * scale
	var to := _pos
	if not is_nan(z):
		to.z = z * scale
	if not is_nan(x):
		to.x = x * scale

	var op := GOp.make(GOp.Kind.MOVE, _channel.id, bi, b.line)
	op.move = GOp.Move.FEED
	op.from_pos = _pos
	op.to_pos = to
	op.tool = _tool
	op.rpm = _current_rpm(to.x)
	op.text = "G74"
	var rx := 0.5 if _dialect.diameter_x else 1.0
	var length := Vector2((to.x - _pos.x) * rx, to.z - _pos.z).length()
	var feed_mm_min := _feed * op.rpm if _feed_per_rev else _feed
	op.feed = feed_mm_min
	if feed_mm_min > 0.0:
		# Вывод стружки удлиняет цикл; принимаем полтора хода на глубину
		op.duration = length / feed_mm_min * 60.0 * 1.5
	else:
		_warn(b, "Цикл G74 без подачи F")
	_push(op)
	_pos = to


func _emit_motion(b: GBlock, bi: int, scale: float) -> void:
	var ax_x := b.value_of("X")
	var ax_u := b.value_of("U")
	var ax_y := b.value_of("Y")
	var ax_v := b.value_of("V")
	var ax_z := b.value_of("Z")
	var ax_w := b.value_of("W")
	var ax_c := b.value_of("C")
	var ax_h := b.value_of("H")

	if is_nan(ax_x) and is_nan(ax_u) and is_nan(ax_y) and is_nan(ax_v) \
		and is_nan(ax_z) and is_nan(ax_w) and is_nan(ax_c) and is_nan(ax_h):
		return

	var to := _pos
	if not is_nan(ax_x):
		to.x = ax_x * scale if _absolute else _pos.x + ax_x * scale
	if not is_nan(ax_u):
		to.x = _pos.x + ax_u * scale
	if not is_nan(ax_y):
		to.y = ax_y * scale if _absolute else _pos.y + ax_y * scale
	if not is_nan(ax_v):
		to.y = _pos.y + ax_v * scale
	if not is_nan(ax_z):
		to.z = ax_z * scale if _absolute else _pos.z + ax_z * scale
	if not is_nan(ax_w):
		to.z = _pos.z + ax_w * scale
	if not is_nan(ax_c):
		to.w = ax_c if _absolute else _pos.w + ax_c
	if not is_nan(ax_h):
		to.w = _pos.w + ax_h

	var rx := 0.5 if _dialect.diameter_x else 1.0
	var dx := (to.x - _pos.x) * rx
	var dy := to.y - _pos.y
	var dz := to.z - _pos.z

	var op := GOp.make(GOp.Kind.MOVE, _channel.id, bi, b.line)
	op.from_pos = _pos
	op.to_pos = to
	op.rpm = _current_rpm(to.x)
	op.tool = _tool
	var length := Vector3(dx, dy, dz).length()

	if _motion == 0:
		op.move = GOp.Move.RAPID
		op.duration = maxf(
			maxf(absf(dx) / _dialect.rapid_x, absf(dy) / _dialect.rapid_y),
			maxf(absf(dz) / _dialect.rapid_z, absf(to.w - _pos.w) / _dialect.rapid_c)) * 60.0
	else:
		if _motion == 2 or _motion == 3:
			op.move = GOp.Move.ARC
			length = _setup_arc(op, b, scale, rx)
		elif _motion == 32:
			op.move = GOp.Move.THREAD
		var feed_mm_min := _feed * op.rpm if _feed_per_rev else _feed
		op.feed = feed_mm_min
		if feed_mm_min > 0.0:
			op.duration = length / feed_mm_min * 60.0
		else:
			_warn(b, "Рабочий ход без заданной подачи F")

	_push(op)
	_pos = to


## Считает центр дуги и возвращает её длину в мм.
func _setup_arc(op: GOp, b: GBlock, scale: float, rx: float) -> float:
	var i_word := b.value_of("I")
	var k_word := b.value_of("K")
	var r_word := b.value_of("R")
	var ccw := _motion == 3
	op.arc_ccw = ccw

	var sx := op.from_pos.x * rx
	var sz := op.from_pos.z
	var ex := op.to_pos.x * rx
	var ez := op.to_pos.z
	var cx := sx
	var cz := sz

	if not is_nan(i_word) or not is_nan(k_word):
		cx = sx + (0.0 if is_nan(i_word) else i_word * scale)
		cz = sz + (0.0 if is_nan(k_word) else k_word * scale)
	elif not is_nan(r_word):
		var rr := r_word * scale
		var mx := (sx + ex) * 0.5
		var mz := (sz + ez) * 0.5
		var chord := maxf(Vector2(ex - sx, ez - sz).length(), 1e-9)
		var h2 := rr * rr - chord * chord * 0.25
		var h := sqrt(h2) if h2 > 0.0 else 0.0
		var ux := -(ez - sz) / chord
		var uz := (ex - sx) / chord
		var sign_h := (1.0 if rr >= 0.0 else -1.0) * (1.0 if ccw else -1.0)
		cx = mx + ux * h * sign_h
		cz = mz + uz * h * sign_h
	else:
		_warn(b, "Дуга задана без I/K и без R", GDiag.Severity.ERROR)

	op.arc_center = Vector2(cx, cz)
	var r0 := Vector2(sx - cx, sz - cz).length()
	var r1 := Vector2(ex - cx, ez - cz).length()
	if absf(r0 - r1) > 0.02:
		_warn(b, "Радиусы дуги не сходятся: %.3f и %.3f мм" % [r0, r1])

	var a0 := atan2(sx - cx, sz - cz)
	var a1 := atan2(ex - cx, ez - cz)
	var sweep := a1 - a0
	if ccw:
		while sweep <= 1e-9:
			sweep += TAU
	else:
		while sweep >= -1e-9:
			sweep -= TAU
	return absf(sweep) * r0


static func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, floorf(v)) else str(v)
