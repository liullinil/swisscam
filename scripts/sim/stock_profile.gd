class_name StockProfile
extends RefCounted

## Осесимметричная модель прутка.
##
## Вдоль оси Z хранятся два радиуса: наружный и радиус осевого отверстия.
## Этого хватает для точения, подрезки, канавок, отрезки и осевого сверления —
## то есть для основной части работы станка продольного точения.
## Данные лежат чередующимися парами (ro, ri) в одном массиве: в таком виде
## они без перекладывания уходят в текстуру, из которой шейдер строит деталь.
##
## Поперечное сверление и фрезеровка приводным инструментом здесь не описываются:
## такие проходы помечаются как не моделируемые и показываются только траекторией.

const STRIDE := 2

var z_min := -60.0
var z_max := 0.5
var dz := 0.02
var samples := 0
var bar_radius := 10.0
## Чередующиеся пары (наружный радиус, радиус отверстия), мм.
var field := PackedFloat32Array()
## Снятый объём, мм³.
var removed := 0.0
## Z, на котором деталь оказалась отрезана. NAN — деталь цела.
var cutoff_z := NAN


static func create(diameter: float, p_z_min: float, p_z_max: float, p_dz := 0.02) -> StockProfile:
	var s := StockProfile.new()
	s.bar_radius = diameter * 0.5
	s.z_min = p_z_min
	s.z_max = p_z_max
	s.dz = maxf(p_dz, 0.002)
	s.samples = maxi(2, int(ceil((p_z_max - p_z_min) / s.dz)) + 1)
	s.field.resize(s.samples * STRIDE)
	s.reset()
	return s


func reset() -> void:
	for i in samples:
		field[i * STRIDE] = bar_radius
		field[i * STRIDE + 1] = 0.0
	removed = 0.0
	cutoff_z = NAN


func index_of(z: float) -> int:
	return int(round((z - z_min) / dz))


func z_of(i: int) -> float:
	return z_min + i * dz


func outer(i: int) -> float:
	return field[i * STRIDE]


func inner(i: int) -> float:
	return field[i * STRIDE + 1]


func snapshot() -> PackedFloat32Array:
	return field.duplicate()


func restore(snap: PackedFloat32Array, p_removed: float, p_cutoff: float) -> void:
	field = snap.duplicate()
	removed = p_removed
	cutoff_z = p_cutoff


## Наружный проход: кромка идёт от (z0, r0) к (z1, r1), ширина кромки width.
## Радиусы знаковые: инструмент может подходить с любой стороны, а проход
## за центр (X с обратным знаком) — это отрезка, и материал там снимается весь.
## Возвращает снятый объём, мм³.
func turn(z0: float, r0: float, z1: float, r1: float, width := 0.0) -> float:
	var half := width * 0.5
	var lo := minf(z0, z1) - half
	var hi := maxf(z0, z1) + half
	var i0 := index_of(lo)
	var i1 := index_of(hi)
	if i1 < i0:
		var c := index_of((z0 + z1) * 0.5)
		i0 = c
		i1 = c
	i0 = maxi(i0, 0)
	i1 = mini(i1, samples - 1)
	if i1 < i0:
		return 0.0

	var span := z1 - z0
	var radial := is_zero_approx(span)
	# Врезание поперёк оси проходит весь путь на одном Z, поэтому важна
	# конечная глубина, а смена знака означает проход через центр.
	var radial_r := 0.0 if signf(r0) != signf(r1) else minf(absf(r0), absf(r1))
	var vol := 0.0
	for i in range(i0, i1 + 1):
		var r := radial_r
		if not radial:
			var t := clampf((z_of(i) - z0) / span, 0.0, 1.0)
			r = absf(r0 + (r1 - r0) * t)
		var idx := i * STRIDE
		var ro := field[idx]
		if r < ro:
			var ri := field[idx + 1]
			var a := maxf(ro, ri)
			var b := maxf(r, ri)
			vol += PI * (a * a - b * b) * dz
			field[idx] = r
			if r <= 1e-4 and is_nan(cutoff_z):
				cutoff_z = z_of(i)
	removed += vol
	return vol


## Осевое сверление или растачивание: отверстие радиуса r от z0 до z1.
func bore(z0: float, z1: float, r: float) -> float:
	var i0 := maxi(index_of(minf(z0, z1)), 0)
	var i1 := mini(index_of(maxf(z0, z1)), samples - 1)
	var vol := 0.0
	for i in range(i0, i1 + 1):
		var idx := i * STRIDE
		var ri := field[idx + 1]
		if r > ri:
			var a := minf(r, field[idx])
			vol += PI * (a * a - ri * ri) * dz
			field[idx + 1] = a
	removed += vol
	return vol


## Объём оставшегося материала, мм³.
func volume() -> float:
	var v := 0.0
	for i in samples:
		var a := field[i * STRIDE]
		var b := minf(field[i * STRIDE + 1], a)
		v += PI * (a * a - b * b) * dz
	return v


## Наибольший наружный радиус — нужен для подгонки камеры.
func max_radius() -> float:
	var m := 0.0
	for i in samples:
		m = maxf(m, field[i * STRIDE])
	return m
