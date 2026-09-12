shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Заготовка строится прямо на видеокарте.
//
// Профиль детали лежит в текстуре шириной в число отсчётов вдоль Z:
// красный канал — наружный радиус, зелёный — радиус осевого отверстия.
// Сетка-заготовка — обычная плоскость, которую вершинный шейдер сворачивает
// в тело вращения, беря радиус из текстуры. Снятие материала стоит одной
// перезаписи текстуры, а не перестроения меша, поэтому модель успевает
// за симуляцией и на слабом железе, и в браузере через WebGL2.

uniform sampler2D profile : filter_nearest, repeat_disable;
uniform float z_min = 0.0;
uniform float z_max = 100.0;
// 0 — наружная поверхность, 1 — стенка осевого отверстия,
// 2 и 3 — торцы со стороны z_min и z_max
uniform int surface = 0;
// Разрез: убрать половину тела, чтобы стало видно отверстие
uniform bool section = false;
uniform vec3 albedo : source_color = vec3(0.66, 0.69, 0.74);
uniform float metallic : hint_range(0.0, 1.0) = 0.8;
uniform float roughness : hint_range(0.0, 1.0) = 0.34;
// Радиус, ниже которого материала нет: там тело не рисуем
uniform float min_radius = 0.004;

varying float v_angle;
varying float v_solid;

vec2 profile_at(float u) {
	return texture(profile, vec2(clamp(u, 0.0, 1.0), 0.5)).rg;
}

void vertex() {
	float a = UV.y * TAU;
	float u;
	float r;
	vec3 n;

	if (surface >= 2) {
		// Торец: кольцо от стенки отверстия до наружной поверхности
		u = surface == 2 ? 0.0 : 1.0;
		vec2 p = profile_at(u);
		r = mix(p.g, p.r, UV.x);
		n = vec3(surface == 2 ? -1.0 : 1.0, 0.0, 0.0);
		v_solid = p.r - p.g;
	} else {
		u = clamp(UV.x, 0.0, 1.0);
		vec2 p = profile_at(u);
		r = surface == 0 ? p.r : p.g;

		float texel = 1.0 / float(textureSize(profile, 0).x);
		vec2 pp = profile_at(u - texel);
		vec2 pn = profile_at(u + texel);
		float dr = (surface == 0 ? pn.r : pn.g) - (surface == 0 ? pp.r : pp.g);
		float dz = (z_max - z_min) * texel * 2.0;
		n = normalize(vec3(-dr, sin(a) * dz, cos(a) * dz));
		if (surface == 1) {
			n = -n;
		}
		v_solid = r;
	}

	VERTEX = vec3(mix(z_min, z_max, u), sin(a) * r, cos(a) * r);
	NORMAL = n;
	v_angle = a;
}

void fragment() {
	if (v_solid <= min_radius) {
		discard;
	}
	if (section && sin(v_angle) > 0.0) {
		discard;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = albedo;
	METALLIC = metallic;
	ROUGHNESS = roughness;
}
