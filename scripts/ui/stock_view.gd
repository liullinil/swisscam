class_name StockView
extends Node3D

## Трёхмерный вид заготовки и траекторий.
##
## Тело вращения строит шейдер по текстуре профиля, поэтому снятие материала
## стоит одной перезаписи текстуры. Траектории лежат отдельными мешами:
## рабочие ходы и холостые переключаются, не пересобирая геометрию.

const CHANNEL_COLORS := {
	"1": Color("4ea3ff"),
	"2": Color("37d39a"),
	"3": Color("c47bff"),
}
const RAPID_COLOR := Color("5a6473")
const GRID_COLOR := Color("2a3038")

var _pivot: Node3D
var _camera: Camera3D
var _outer: MeshInstance3D
var _inner: MeshInstance3D
var _caps: Array[MeshInstance3D] = []
var _feed_paths: MeshInstance3D
var _rapid_paths: MeshInstance3D
var _axis: MeshInstance3D
var _markers := {}
var _material: ShaderMaterial
var _inner_material: ShaderMaterial
var _materials: Array[ShaderMaterial] = []
var _profile_tex: ImageTexture
var _profile_img: Image

var _yaw := 0.5
var _pitch := -0.35
var _distance := 200.0
var _target := Vector3.ZERO
var _stock: StockProfile

## Насколько подробна сетка тела вращения
const COLUMNS := 384
const SEGMENTS := 72


func _ready() -> void:
	_build_environment()
	_build_stock_meshes()
	_build_path_meshes()
	_apply_camera()


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("11141a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("46506b")
	e.ambient_light_energy = 0.65
	e.fog_enabled = false
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.light_energy = 2.2
	key.light_color = Color("fff4e2")
	key.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	key.shadow_enabled = true
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.7
	fill.light_color = Color("8fb4ff")
	fill.rotation_degrees = Vector3(-15.0, 140.0, 0.0)
	add_child(fill)

	_pivot = Node3D.new()
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.near = 0.5
	_camera.far = 8000.0
	_camera.fov = 45.0
	_pivot.add_child(_camera)


func _build_stock_meshes() -> void:
	var shader := load("res://shaders/stock.gdshader") as Shader
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	plane.subdivide_width = COLUMNS
	plane.subdivide_depth = SEGMENTS

	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("surface", 0)
	_material.set_shader_parameter("albedo", Color("aab3bf"))

	_inner_material = ShaderMaterial.new()
	_inner_material.shader = shader
	_inner_material.set_shader_parameter("surface", 1)
	_inner_material.set_shader_parameter("albedo", Color("6d7682"))
	_inner_material.set_shader_parameter("roughness", 0.55)

	_outer = MeshInstance3D.new()
	_outer.mesh = plane
	_outer.material_override = _material
	add_child(_outer)

	_inner = MeshInstance3D.new()
	_inner.mesh = plane
	_inner.material_override = _inner_material
	add_child(_inner)

	_materials = [_material, _inner_material]

	# Торцы: кольцо от стенки отверстия до наружной поверхности.
	# Без них труба выглядит открытой, и вместо торца видна изнанка тела.
	var cap_mesh := PlaneMesh.new()
	cap_mesh.size = Vector2(1.0, 1.0)
	cap_mesh.subdivide_width = 8
	cap_mesh.subdivide_depth = SEGMENTS
	for mode in [2, 3]:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("surface", mode)
		mat.set_shader_parameter("albedo", Color("8c95a2"))
		mat.set_shader_parameter("roughness", 0.45)
		var mi := MeshInstance3D.new()
		mi.mesh = cap_mesh
		mi.material_override = mat
		add_child(mi)
		_caps.append(mi)
		_materials.append(mat)


func _build_path_meshes() -> void:
	_feed_paths = _make_line_mesh()
	_rapid_paths = _make_line_mesh()
	# Холостые прячем сразу: отводы вроде X116 уводят линии далеко за заготовку
	_rapid_paths.visible = false
	_axis = _make_line_mesh()
	add_child(_feed_paths)
	add_child(_rapid_paths)
	add_child(_axis)


func _make_line_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


## Привязывает вид к новому заданию: профиль, траектории, рамка камеры.
func set_job(job: GJob) -> void:
	_stock = job.sim.stock
	_profile_img = Image.create_empty(_stock.samples, 1, false, Image.FORMAT_RGF)
	_profile_tex = ImageTexture.create_from_image(_profile_img)
	for m in _materials:
		m.set_shader_parameter("profile", _profile_tex)
		m.set_shader_parameter("z_min", _stock.z_min)
		m.set_shader_parameter("z_max", _stock.z_max)

	var r := _stock.bar_radius * 1.2
	var aabb := AABB(Vector3(_stock.z_min, -r, -r), Vector3(_stock.z_max - _stock.z_min, r * 2.0, r * 2.0))
	_outer.custom_aabb = aabb
	_inner.custom_aabb = aabb
	for c in _caps:
		c.custom_aabb = aabb

	_feed_paths.visible = true
	_build_paths(job)
	_build_axis()
	_rebuild_markers(job)
	refresh_profile()
	frame_all()


## Переносит текущее состояние заготовки в текстуру профиля.
func refresh_profile() -> void:
	if _stock == null or _profile_tex == null:
		return
	_profile_img.set_data(_stock.samples, 1, false, Image.FORMAT_RGF, _stock.field.to_byte_array())
	_profile_tex.update(_profile_img)


func _build_paths(job: GJob) -> void:
	var feed_lines := PackedVector3Array()
	var feed_colors := PackedColorArray()
	var rapid_lines := PackedVector3Array()
	var rapid_colors := PackedColorArray()

	for slot in job.timeline.items:
		var op: GOp = slot.op
		if op.kind != GOp.Kind.MOVE:
			continue
		var points := _path_points(op)
		if op.move == GOp.Move.RAPID:
			_collect_polyline(points, RAPID_COLOR, rapid_lines, rapid_colors)
		else:
			_collect_polyline(points, CHANNEL_COLORS.get(op.channel, Color.WHITE), feed_lines, feed_colors)

	_fill_lines(_feed_paths, feed_lines, feed_colors)
	_fill_lines(_rapid_paths, rapid_lines, rapid_colors)
	if rapid_lines.is_empty():
		_rapid_paths.visible = false


func _collect_polyline(pts: PackedVector2Array, color: Color, out_v: PackedVector3Array, out_c: PackedColorArray) -> void:
	for i in pts.size() - 1:
		out_v.append(Vector3(pts[i].x, pts[i].y, 0.0))
		out_c.append(color)
		out_v.append(Vector3(pts[i + 1].x, pts[i + 1].y, 0.0))
		out_c.append(color)


func _fill_lines(node: MeshInstance3D, verts: PackedVector3Array, colors: PackedColorArray) -> void:
	var mesh := node.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if verts.is_empty():
		node.visible = false
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in verts.size():
		mesh.surface_set_color(colors[i])
		mesh.surface_add_vertex(verts[i])
	mesh.surface_end()


## Разворачивает перемещение в точки (Z, радиус) в плоскости ZX.
func _path_points(op: GOp) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r0 := op.from_pos.x * 0.5
	var r1 := op.to_pos.x * 0.5
	if op.move == GOp.Move.ARC:
		var c := op.arc_center
		var rad := Vector2(r0 - c.x, op.from_pos.z - c.y).length()
		var a0 := atan2(r0 - c.x, op.from_pos.z - c.y)
		var a1 := atan2(r1 - c.x, op.to_pos.z - c.y)
		var sweep := a1 - a0
		if op.arc_ccw:
			while sweep <= 1e-9:
				sweep += TAU
		else:
			while sweep >= -1e-9:
				sweep -= TAU
		var steps := maxi(4, int(absf(sweep) / 0.12))
		for s in steps + 1:
			var a := a0 + sweep * float(s) / float(steps)
			pts.append(Vector2(c.y + rad * cos(a), c.x + rad * sin(a)))
	else:
		pts.append(Vector2(op.from_pos.z, r0))
		pts.append(Vector2(op.to_pos.z, r1))
	return pts


func _build_axis() -> void:
	var mesh := _axis.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _stock == null:
		return
	_axis.visible = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(GRID_COLOR)
	mesh.surface_add_vertex(Vector3(_stock.z_min - 5.0, 0.0, 0.0))
	mesh.surface_set_color(GRID_COLOR)
	mesh.surface_add_vertex(Vector3(_stock.z_max + 5.0, 0.0, 0.0))
	var step := 10.0
	var span := _stock.z_max - _stock.z_min
	if span > 200.0:
		step = 25.0
	var z := ceilf(_stock.z_min / step) * step
	while z <= _stock.z_max:
		mesh.surface_set_color(GRID_COLOR)
		mesh.surface_add_vertex(Vector3(z, 0.0, 0.0))
		mesh.surface_set_color(GRID_COLOR)
		mesh.surface_add_vertex(Vector3(z, -_stock.bar_radius * 1.15, 0.0))
		z += step
	mesh.surface_end()


func _rebuild_markers(job: GJob) -> void:
	for m in _markers.values():
		m.queue_free()
	_markers.clear()
	for ch in job.channels:
		var cone := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = maxf(_stock.bar_radius * 0.12, 0.4)
		mesh.height = maxf(_stock.bar_radius * 0.4, 1.5)
		mesh.radial_segments = 12
		cone.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = CHANNEL_COLORS.get(ch.id, Color.WHITE)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cone.material_override = mat
		cone.visible = false
		add_child(cone)
		_markers[ch.id] = cone


## Ставит указатель канала в точку (Z, радиус).
func set_marker(channel: String, z: float, radius: float, shown := true) -> void:
	var m: MeshInstance3D = _markers.get(channel)
	if m == null:
		return
	m.visible = shown
	if not shown:
		return
	var h: float = (m.mesh as CylinderMesh).height
	var sign_r := 1.0 if radius >= 0.0 else -1.0
	m.position = Vector3(z, radius + sign_r * h * 0.5, 0.0)
	m.rotation_degrees = Vector3(0.0, 0.0, 180.0 if radius >= 0.0 else 0.0)


func set_show_rapid(on: bool) -> void:
	_rapid_paths.visible = on


func set_show_paths(on: bool) -> void:
	_feed_paths.visible = on


func set_section(on: bool) -> void:
	for m in _materials:
		m.set_shader_parameter("section", on)


func frame_all() -> void:
	if _stock == null:
		return
	var span := _stock.z_max - _stock.z_min
	_target = Vector3((_stock.z_min + _stock.z_max) * 0.5, 0.0, 0.0)
	_distance = maxf(span * 1.1, _stock.bar_radius * 8.0)
	_yaw = 0.5
	_pitch = -0.35
	_apply_camera()


func orbit(delta: Vector2) -> void:
	_yaw -= delta.x * 0.008
	_pitch = clampf(_pitch - delta.y * 0.008, -1.45, 1.45)
	_apply_camera()


func pan(delta: Vector2) -> void:
	var scale := _distance * 0.0015
	var right := _camera.global_transform.basis.x
	var up := _camera.global_transform.basis.y
	_target -= right * delta.x * scale - up * delta.y * scale
	_apply_camera()


func zoom(factor: float) -> void:
	_distance = clampf(_distance * factor, 2.0, 20000.0)
	_apply_camera()


func _apply_camera() -> void:
	if _pivot == null:
		return
	_pivot.position = _target
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)
