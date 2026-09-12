class_name GProgram
extends RefCounted

## Результат разбора текста УП.

var channels: Array[GChannel] = []
var diags: Array[GDiag] = []


func channel_by_id(p_id: String) -> GChannel:
	for c in channels:
		if c.id == p_id:
			return c
	return null


func block_count() -> int:
	var total := 0
	for c in channels:
		total += c.blocks.size()
	return total
