class_name GTimeline
extends RefCounted

## Разложенная по времени программа: все каналы вместе.

## Все операции, отсортированные по времени старта.
var items: Array[GSlot] = []
## id канала -> Array[GSlot] в порядке исполнения.
var by_channel := {}
var waits: Array[GWaitSpan] = []
var total_time := 0.0
var diags: Array[GDiag] = []


func channel_ids() -> PackedStringArray:
	var ids := PackedStringArray(by_channel.keys())
	ids.sort()
	return ids


## Сколько канал простоял в ожидании других, с.
func wait_time(channel_id: String) -> float:
	var total := 0.0
	for w in waits:
		if w.channel == channel_id:
			total += w.seconds()
	return total


## Индекс последней операции, начавшейся не позже t.
func index_at_time(t: float) -> int:
	var lo := 0
	var hi := items.size() - 1
	var res := -1
	while lo <= hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		if items[mid].start <= t:
			res = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return res
