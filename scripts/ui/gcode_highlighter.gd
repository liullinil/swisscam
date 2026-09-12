class_name GCodeHighlighter
extends SyntaxHighlighter

## Подсветка G-кода. Обычный подсветчик по словам здесь не годится:
## в кадре вида G00Z70.X0.T0131 между адресами нет пробелов, поэтому
## строка разбирается по буквам — тем же правилом, что и в лексере.

const COMMENT := Color("6b7484")
const G_CODE := Color("4ea3ff")
const M_CODE := Color("37d39a")
const TOOL := Color("ffc857")
const FEED := Color("c47bff")
const AXIS := Color("dfe4ec")
const LABEL := Color("7a8497")
const SYNC := Color("ff8ad8")
const MACRO := Color("ff9d5c")
const SKIP := Color("4a5262")

const AXIS_LETTERS := "XYZUVWABCIJKRQPHLE"


static func _color_for(letter: String) -> Color:
	match letter:
		"G": return G_CODE
		"M": return M_CODE
		"T", "D": return TOOL
		"F", "S": return FEED
		"N", "O": return LABEL
		_:
			return AXIS if AXIS_LETTERS.contains(letter) else AXIS


func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var out := {}
	var text := get_text_edit().get_line(line)
	var n := text.length()
	var i := 0

	var stripped := text.strip_edges()
	if stripped.begins_with("/") or stripped.begins_with("%"):
		out[0] = {"color": SKIP}
		if not stripped.begins_with("%"):
			i = text.find("/") + 1
		else:
			return out

	while i < n:
		var c := text[i]
		if c == "(":
			out[i] = {"color": COMMENT}
			var close := text.find(")", i)
			if close == -1:
				break
			i = close + 1
			out[i] = {"color": AXIS}
			continue
		if c == ";":
			out[i] = {"color": COMMENT}
			break
		if c == "!":
			out[i] = {"color": SYNC}
			i += 1
			while i < n and (text[i].is_valid_int() or text[i].to_upper() == "L"):
				i += 1
			out[i] = {"color": AXIS}
			continue
		if c == "#":
			out[i] = {"color": MACRO}
			break
		var up := c.to_upper()
		if up >= "A" and up <= "Z":
			out[i] = {"color": _color_for(up)}
			i += 1
			while i < n and (text[i].is_valid_int() or text[i] == "." or text[i] == "-" or text[i] == "+"):
				i += 1
			continue
		i += 1
	return out
