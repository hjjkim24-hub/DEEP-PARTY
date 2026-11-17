shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// 대포 연기 한 덩이: 둥글고 가장자리가 부드럽게 사라지는 뭉게 연기
uniform vec3 tint : source_color = vec3(0.62, 0.62, 0.66);
uniform float opacity = 0.6;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

varying float seed;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	seed = fract(MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.61);
}

void fragment() {
	vec2 q = UV - 0.5;
	float d = length(q) * 2.0;
	float n = vnoise(q * 5.0 + seed * 17.0) * 0.6 + vnoise(q * 11.0 - seed * 9.0) * 0.4;
	float a = smoothstep(1.0, 0.25, d + (n - 0.5) * 0.55);
	ALBEDO = tint * COLOR.rgb * (0.85 + n * 0.3);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = clamp(a * COLOR.a * opacity, 0.0, 1.0);
}
