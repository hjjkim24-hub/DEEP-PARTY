shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
// 배 옆을 스쳐 지나가는 뭉게구름 한 덩이 (빌보드)

uniform vec3 top_col : source_color = vec3(0.6, 0.66, 0.9);
uniform vec3 shade_col : source_color = vec3(0.08, 0.09, 0.22);
uniform float seed = 0.0;
uniform float opacity = 0.85;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1, 0)), f.x), mix(h12(i + vec2(0, 1)), h12(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * n2(p);
		p *= 2.05;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 q = (UV - 0.5) * vec2(2.0, 2.0);
	q.y = -q.y;
	float n = fbm(UV * 3.0 + seed * 7.0 + vec2(TIME * 0.01, 0.0));
	// 바닥이 평평하고 위가 뭉게뭉게
	float shape = 1.0 - length(q * vec2(1.0, 1.35) + vec2(0.0, 0.15));
	shape += (n - 0.5) * 0.9;
	shape -= smoothstep(-0.25, -0.6, q.y) * 0.8;
	float d = smoothstep(0.0, 0.35, shape) * smoothstep(1.0, 0.75, max(abs(q.x), abs(q.y)));
	float lit = clamp(0.35 + q.y * 0.6 + (n - 0.5) * 0.8, 0.0, 1.0);
	ALBEDO = mix(shade_col, top_col, lit);
	ALPHA = d * opacity;
}
