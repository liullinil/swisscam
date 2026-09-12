class_name GWaitSpan
extends RefCounted

## Простой канала на коде ожидания: видно, кто кого ждёт и сколько.

var channel := ""
var tag := ""
var from_time := 0.0
var to_time := 0.0
var line := 0


func seconds() -> float:
	return to_time - from_time
