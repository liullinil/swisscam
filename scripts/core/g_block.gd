class_name GBlock
extends RefCounted

## Разобранный кадр управляющей программы — одна строка исходника.
##
## Адреса хранятся тремя параллельными массивами, а не словарём: в кадре
## один и тот же адрес может встретиться дважды (например G-коды), а перебор
## упакованных массивов заметно дешевле при разборе программ в тысячи кадров.

## Номер строки в исходном тексте, с нуля.
var line: int = 0
var raw: String = ""

## Буквы адресов: "G", "X", "Z", …
var letters := PackedStringArray()
## Числа при адресах. NAN — адрес задан выражением, которое мы не вычисляем.
var values := PackedFloat64Array()
## Позиция буквы в строке — для подсветки ошибок.
var cols := PackedInt32Array()

var comments := PackedStringArray()
## Nxxxx, NAN если нет.
var n_number: float = NAN
## Oxxxx, NAN если нет.
var program_no: float = NAN
## Кадр помечен «/» — пропуск кадра.
var block_delete := false
## Заголовок канала: "1", "2", "3". Пустая строка — обычный кадр.
var channel_header := ""
## Метка синхронизации в стиле Citizen/Star: "L1", "2L3".
var sync_tag := ""
## Макротекст (IF/WHILE/GOTO/#100=…), который мы пока не исполняем.
var macro := ""


func add_word(letter: String, value: float, col: int) -> void:
	letters.append(letter)
	values.append(value)
	cols.append(col)


## Последнее значение адреса в кадре; NAN, если адреса нет.
func value_of(letter: String) -> float:
	for i in range(letters.size() - 1, -1, -1):
		if letters[i] == letter:
			return values[i]
	return NAN


func has_letter(letter: String) -> bool:
	return letters.has(letter)


## Все значения адреса в порядке появления — нужно для G- и M-кодов.
func all_of(letter: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in letters.size():
		if letters[i] == letter:
			out.append(values[i])
	return out


func is_empty_block() -> bool:
	return letters.is_empty() and sync_tag.is_empty() and macro.is_empty()
