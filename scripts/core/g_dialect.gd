class_name GDialect
extends Resource

## Профиль стойки. Всё, чем один диалект отличается от другого, живёт здесь,
## чтобы интерпретатор оставался общим.

@export var id := "hanwha"
@export var title := "Hanwha XD (FANUC)"
@export_multiline var notes := ""
## X в кадре — диаметр. Обычное для токарных станков.
@export var diameter_x := true
## Диапазон M-кодов, работающих как коды ожидания между каналами.
@export var wait_m_from := 500
@export var wait_m_to := 599
## Поддерживаются метки синхронизации вида !L1.
@export var bang_sync := false
## M-коды отрезки и передачи детали.
@export var cutoff_m: PackedInt32Array = PackedInt32Array([80, 81])
## Быстрый ход по осям, мм/мин — нужен для оценки машинного времени.
@export var rapid_x := 24000.0
@export var rapid_y := 24000.0
@export var rapid_z := 32000.0
@export var rapid_c := 20000.0
## Время индексации инструмента, с.
@export var tool_change_time := 0.4
## По умолчанию подача на оборот (G99).
@export var feed_per_rev_default := true
@export var max_rpm := 10000.0
@export var default_bar_diameter := 20.0


func is_wait_code(m: int) -> bool:
	return m >= wait_m_from and m <= wait_m_to


static func hanwha() -> GDialect:
	var d := GDialect.new()
	d.id = "hanwha"
	d.title = "Hanwha XD (FANUC)"
	d.notes = "Многоканальная программа FANUC: каналы разделяются заголовками $1/$2/$3, " \
		+ "ожидание между каналами — парные M-коды из диапазона M100…M199. " \
		+ "Диапазон задаётся параметром стойки, при необходимости поправьте его в настройках."
	return d


static func citizen() -> GDialect:
	var d := hanwha()
	d.id = "citizen"
	d.title = "Citizen Cincom"
	d.notes = "Синхронизация метками вида !1L1 / !2L1, каналы $1/$2/$3."
	d.bang_sync = true
	d.wait_m_from = 100
	d.wait_m_to = 199
	return d


static func fanuc_generic() -> GDialect:
	var d := hanwha()
	d.id = "fanuc"
	d.title = "FANUC turn (обобщённый)"
	d.notes = "Базовый токарный FANUC без специфики продольного точения."
	d.wait_m_from = 100
	d.wait_m_to = 199
	return d


static func presets() -> Array[GDialect]:
	return [hanwha(), citizen(), fanuc_generic()]


static func by_id(p_id: String) -> GDialect:
	for d in presets():
		if d.id == p_id:
			return d
	return hanwha()
