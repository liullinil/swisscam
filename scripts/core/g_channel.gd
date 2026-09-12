class_name GChannel
extends RefCounted

## Один канал многоканальной программы. У Hanwha каналы обычно лежат
## отдельными файлами, поэтому канал помнит, из какого файла он пришёл.

var id := "1"
var title := ""
## Имя файла-источника, если канал загружен отдельным файлом.
var source_name := ""
var blocks: Array[GBlock] = []
## Номер инструмента -> комментарий из кадра смены инструмента.
var tool_comments := {}


static func make(p_id: String) -> GChannel:
	var c := GChannel.new()
	c.id = p_id
	c.title = default_title(p_id)
	return c


static func default_title(p_id: String) -> String:
	match p_id:
		"1": return "$1 главный шпиндель"
		"2": return "$2 противошпиндель"
		"3": return "$3 третий суппорт"
		_: return "$" + p_id


func is_sub_spindle() -> bool:
	return id == "2"


## Разделы программы из комментариев вида ( COMMENT "OD Roughing 1" ).
## Возвращает массив словарей {line, name, block_index}.
func sections() -> Array:
	var re := RegEx.create_from_string("(?i)COMMENT\\s+\"(.+)\"")
	var out := []
	for i in blocks.size():
		var b: GBlock = blocks[i]
		for c in b.comments:
			var m := re.search(c)
			if m:
				out.append({"line": b.line, "name": m.get_string(1).strip_edges(), "block_index": i})
				break
	return out
