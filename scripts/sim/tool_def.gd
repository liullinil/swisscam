class_name ToolDef
extends RefCounted

## Инструмент из таблицы. Заполняется из списка в шапке программы,
## а чего нет в шапке — угадывается по характеру движений и правится руками.

enum Kind {
	TURN,     ## проходной, режет наружный контур
	GROOVE,   ## канавочный, режет на ширину кромки
	CUTOFF,   ## отрезной
	DRILL,    ## осевое сверло
	THREAD,   ## резьбовой
	LIVE,     ## приводной: поперечное сверление и фрезеровка, осевой моделью не описывается
	GRIPPER,  ## захват, ловитель, подача прутка — материала не снимает
}

var id := 0
var name := ""
var kind: Kind = Kind.TURN
## Ширина режущей кромки, мм — для канавочных и отрезных.
var width := 0.0
## Радиус при вершине, мм.
var nose_r := 0.4
## Диаметр осевого инструмента, мм.
var diameter := 3.0
## Откуда взялось описание: из шапки программы или из догадки.
var from_header := false


static func make(p_id: int, p_kind: Kind = Kind.TURN) -> ToolDef:
	var t := ToolDef.new()
	t.id = p_id
	t.kind = p_kind
	t.name = "T%02d" % p_id
	match p_kind:
		Kind.GROOVE:
			t.width = 2.0
			t.nose_r = 0.2
		Kind.CUTOFF:
			t.width = 2.0
			t.nose_r = 0.1
		Kind.DRILL:
			t.nose_r = 0.0
		Kind.THREAD:
			t.width = 0.2
			t.nose_r = 0.05
		Kind.GRIPPER:
			t.nose_r = 0.0
	return t


func cuts_material() -> bool:
	return kind != Kind.GRIPPER and kind != Kind.LIVE


func kind_title() -> String:
	match kind:
		Kind.TURN: return "проходной"
		Kind.GROOVE: return "канавочный"
		Kind.CUTOFF: return "отрезной"
		Kind.DRILL: return "сверло"
		Kind.THREAD: return "резьбовой"
		Kind.LIVE: return "приводной"
		Kind.GRIPPER: return "захват"
		_: return "?"


func describe() -> String:
	var s := "T%02d %s" % [id, kind_title()]
	if not name.is_empty() and name != "T%02d" % id:
		s += " — " + name
	return s
