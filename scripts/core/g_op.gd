class_name GOp
extends RefCounted

## Элементарное действие канала — то, что занимает время на диаграмме
## и оставляет след на заготовке.

enum Kind { MOVE, DWELL, TOOL, WAIT, CUTOFF, MISC, END }
enum Move { RAPID, FEED, ARC, THREAD }

var kind: Kind = Kind.MISC
var channel := "1"
## Индекс кадра внутри канала.
var index := 0
## Строка в исходном тексте.
var line := 0
## Длительность, с.
var duration := 0.0

var move: Move = Move.FEED
## Координаты в системе детали: x — диаметр, z — вдоль оси, мм.
var from_pos := Vector4.ZERO
var to_pos := Vector4.ZERO
## Центр дуги в радиусных координатах: x — радиус, y — z.
var arc_center := Vector2.ZERO
var arc_ccw := false

## Эффективная подача, мм/мин.
var feed := 0.0
var rpm := 0.0
var tool := 0
var sub_spindle := false
## Метка ожидания для синхронизации каналов.
var wait_tag := ""
var text := ""


static func make(p_kind: Kind, p_channel: String, p_index: int, p_line: int) -> GOp:
	var op := GOp.new()
	op.kind = p_kind
	op.channel = p_channel
	op.index = p_index
	op.line = p_line
	return op


func is_cutting_move() -> bool:
	return kind == Kind.MOVE and move != Move.RAPID
