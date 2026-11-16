shader_type spatial;
// 위에서 비스듬히 내려오는 빛줄기 (더해지는 빛). 가는 결이 일렁이고, 가까이 · 정면에서는 흐려져 판처럼 보이지 않음
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 0.12;
uniform float phase = 0.0;

varying float axis_fade;
varying float dist;

void vertex() {
	// 빛줄기를 위에서 내려다보면 납작한 띠처럼 보이니 흐리게
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - wp;
	vec3 vd = normalize(to_cam);
	axis_fade = smoothstep(0.85, 0.4, abs(dot(axis, vd)));
	dist = length(to_cam);
}

void fragment() {
	float edge = sin(UV.x * 3.14159);
	edge = edge * edge * edge;
	float fade = smoothstep(1.0, 0.3, UV.y) * smoothstep(0.0, 0.35, UV.y);
	float flick = 0.75 + 0.25 * sin(TIME * 0.6 + phase);
	// 빛줄기 안의 가는 결 (천천히 흐름)
	float streak = 0.55 + 0.45 * sin(UV.x * 23.0 + phase * 3.0 + sin(UV.x * 7.0 + TIME * 0.3 + phase) * 2.0);
	float near_fade = smoothstep(5.0, 18.0, dist) * mix(1.0, 0.45, smoothstep(50.0, 110.0, dist));
	ALBEDO = vec3(0.6, 0.95, 0.85) * edge * fade * streak * strength * flick * axis_fade * near_fade;
}
