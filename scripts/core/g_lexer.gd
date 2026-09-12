class_name GLexer
extends RefCounted

## Разбор текста управляющей программы в кадры и каналы.
##
## Лексер намеренно снисходителен: незнакомое он помечает замечанием и идёт дальше,
## потому что редактор должен показывать программу даже наполовину набранной.

const CH_TAB := 9
const CH_SPACE := 32
const CH_BANG := 33
const CH_PERCENT := 37
const CH_LPAREN := 40
const CH_RPAREN := 41
const CH_PLUS := 43
const CH_MINUS := 45
const CH_DOT := 46
const CH_SLASH := 47
const CH_0 := 48
const CH_9 := 57
const CH_SEMI := 59
const CH_A := 65
const CH_Z := 90
const CH_LBRACKET := 91
const CH_RBRACKET := 93
const CH_a := 97
const CH_z := 122
const CH_HASH := 35
const CH_DOLLAR := 36

static var _macro_re: RegEx
static var _channel_re: RegEx
static var _sync_re: RegEx


static func _ensure_re() -> void:
	if _macro_re == null:
		_macro_re = RegEx.create_from_string("(?i)^\\s*(IF|WHILE|GOTO|DO|END|#\\s*\\d+\\s*=)")
		_channel_re = RegEx.create_from_string("^\\s*\\$(\\d+)\\s*$")
		_sync_re = RegEx.create_from_string("(?i)^![0-9]*(?:L[0-9]+)?")


static func _is_digit(c: int) -> bool:
	return c >= CH_0 and c <= CH_9


static func _is_letter(c: int) -> bool:
	return (c >= CH_A and c <= CH_Z) or (c >= CH_a and c <= CH_z)


## Читает число начиная с позиции i, возвращает [значение, позиция после числа].
static func _read_number(text: String, i: int) -> Array:
	var start := i
	var n := text.length()
	if i < n:
		var c := text.unicode_at(i)
		if c == CH_PLUS or c == CH_MINUS:
			i += 1
	while i < n:
		var c := text.unicode_at(i)
		if _is_digit(c) or c == CH_DOT:
			i += 1
		else:
			break
	var raw := text.substr(start, i - start)
	if raw.is_empty() or raw == "-" or raw == "+" or raw == ".":
		return [NAN, i]
	return [raw.to_float(), i]


## Пропускает выражение в скобках или ссылку на переменную — значение не вычисляем.
static func _skip_expr(text: String, i: int) -> int:
	var n := text.length()
	if i < n and text.unicode_at(i) == CH_HASH:
		i += 1
		if i < n and text.unicode_at(i) == CH_LBRACKET:
			return _skip_brackets(text, i)
		while i < n and _is_digit(text.unicode_at(i)):
			i += 1
		return i
	if i < n and text.unicode_at(i) == CH_LBRACKET:
		return _skip_brackets(text, i)
	return i


static func _skip_brackets(text: String, i: int) -> int:
	var depth := 0
	var n := text.length()
	while i < n:
		var c := text.unicode_at(i)
		if c == CH_LBRACKET:
			depth += 1
		elif c == CH_RBRACKET:
			depth -= 1
			if depth == 0:
				return i + 1
		i += 1
	return n


static func parse_line(text: String, line: int, diags: Array[GDiag]) -> GBlock:
	_ensure_re()
	var b := GBlock.new()
	b.line = line
	b.raw = text

	var m := _channel_re.search(text)
	if m:
		b.channel_header = m.get_string(1)
		return b

	var n := text.length()
	var i := 0
	while i < n and (text.unicode_at(i) == CH_SPACE or text.unicode_at(i) == CH_TAB):
		i += 1

	if i < n and text.unicode_at(i) == CH_SLASH:
		b.block_delete = true
		i += 1

	if _macro_re.search(text.substr(i)):
		b.macro = text.substr(i).strip_edges()
		return b

	while i < n:
		var c := text.unicode_at(i)
		if c == CH_SPACE or c == CH_TAB or c == 13:
			i += 1
			continue
		if c == CH_LPAREN:
			var close := text.find(")", i)
			if close == -1:
				b.comments.append(text.substr(i + 1).strip_edges())
				diags.append(GDiag.make(line, i, n - i, GDiag.Severity.WARNING, "Комментарий не закрыт скобкой"))
				break
			b.comments.append(text.substr(i + 1, close - i - 1).strip_edges())
			i = close + 1
			continue
		if c == CH_SEMI:
			b.comments.append(text.substr(i + 1).strip_edges())
			break
		if c == CH_PERCENT or c == CH_DOLLAR:
			i += 1
			continue
		if c == CH_BANG:
			var sm := _sync_re.search(text.substr(i))
			var raw_tag := sm.get_string(0) if sm else "!"
			b.sync_tag = raw_tag.substr(1)
			if b.sync_tag.is_empty():
				b.sync_tag = "1"
			i += raw_tag.length()
			continue
		if c == CH_HASH:
			b.macro = b.macro + text.substr(i).strip_edges()
			break
		if _is_letter(c):
			var col := i
			var letter := text.substr(i, 1).to_upper()
			i += 1
			var value := NAN
			if i < n and (text.unicode_at(i) == CH_LBRACKET or text.unicode_at(i) == CH_HASH):
				i = _skip_expr(text, i)
			else:
				var res := _read_number(text, i)
				value = res[0]
				i = res[1]
				if is_nan(value):
					diags.append(GDiag.make(line, col, 1, GDiag.Severity.ERROR, "Адрес %s без числа" % letter))
			if letter == "N" and b.letters.is_empty():
				b.n_number = value
			elif letter == "O" and b.letters.is_empty():
				b.program_no = value
			else:
				b.add_word(letter, value, col)
			continue
		diags.append(GDiag.make(line, i, 1, GDiag.Severity.ERROR, "Недопустимый символ «%s»" % text.substr(i, 1)))
		i += 1

	return b


## Разбирает всю программу. Каналы разделяются заголовками $1/$2/$3;
## если заголовков нет — вся программа считается каналом $1.
static func parse_program(text: String) -> GProgram:
	var prog := GProgram.new()
	var lines := text.split("\n")
	var current: GChannel = null

	for i in lines.size():
		var raw := lines[i]
		if raw.ends_with("\r"):
			raw = raw.substr(0, raw.length() - 1)
		var b := parse_line(raw, i, prog.diags)
		if not b.channel_header.is_empty():
			current = prog.channel_by_id(b.channel_header)
			if current == null:
				current = GChannel.make(b.channel_header)
				prog.channels.append(current)
			continue
		if current == null:
			current = prog.channel_by_id("1")
			if current == null:
				current = GChannel.make("1")
				prog.channels.append(current)
		current.blocks.append(b)

	if prog.channels.is_empty():
		prog.channels.append(GChannel.make("1"))
	prog.channels.sort_custom(func(a: GChannel, c: GChannel) -> bool: return a.id < c.id)
	return prog
