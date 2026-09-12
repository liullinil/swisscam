class_name GDiag
extends RefCounted

## Замечание к программе: ошибка, предупреждение или пояснение.

enum Severity { ERROR, WARNING, INFO }

var line: int = 0
var col: int = 0
var length: int = 0
var severity: Severity = Severity.WARNING
var message: String = ""
## Канал, к которому относится замечание; пустая строка — общее.
var channel: String = ""


static func make(p_line: int, p_col: int, p_len: int, p_sev: Severity, p_msg: String, p_channel := "") -> GDiag:
	var d := GDiag.new()
	d.line = p_line
	d.col = p_col
	d.length = p_len
	d.severity = p_sev
	d.message = p_msg
	d.channel = p_channel
	return d


func severity_name() -> String:
	match severity:
		Severity.ERROR: return "ошибка"
		Severity.WARNING: return "внимание"
		_: return "справка"


func color() -> Color:
	match severity:
		Severity.ERROR: return Color("ff6b6b")
		Severity.WARNING: return Color("ffc857")
		_: return Color("8d97a8")
