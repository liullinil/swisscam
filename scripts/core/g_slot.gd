class_name GSlot
extends RefCounted

## Операция, поставленная на временную шкалу.

var op: GOp
var start := 0.0
var end := 0.0


static func make(p_op: GOp, p_start: float, p_end: float) -> GSlot:
	var s := GSlot.new()
	s.op = p_op
	s.start = p_start
	s.end = p_end
	return s
