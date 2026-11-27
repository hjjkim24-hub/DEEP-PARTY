shader_type spatial;
// 물에 뜬 것 둘레의 거품: 가장자리를 따라 하얗게 부서지며 일렁이고, 밑(통나무 틈 사이)으로도 조금 비침.
// 수면 높이에 눕힌 판에 그림. 직사각형(center, half) 바깥으로 갈수록 흩어지며 사라짐.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec2 center = vec2(0.0);
uniform vec2 half_size = vec2(3.6, 3.7);
uniform float width = 0.55;
uniform float inner = 0.0;
uniform float strength = 1.0;
uniform sampler2D foam_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 p = wp.xz - center;
	float d = sd_box(p, half_size);
	float f1 = texture(foam_tex, wp.xz * 0.23 + vec2(TIME * 0.021, TIME * 0.013)).r;
	float f2 = texture(foam_tex, wp.xz * 0.47 - vec2(TIME * 0.017, -TIME * 0.025)).r;
	float foam = smoothstep(0.25, 0.75, f1 * 0.6 + f2 * 0.55);
	// 가장자리 띠 (일렁이는 폭)
	float wob = sin(wp.x * 2.3 + TIME * 1.7) * 0.12 + sin(wp.z * 1.9 - TIME * 1.3) * 0.12;
	float band = smoothstep(width + wob, 0.0, d) * step(0.0, d);
	float under = smoothstep(-0.6, 0.0, d) * (1.0 - step(0.0, d)) * inner + step(d, -0.6) * inner * 0.6;
	float a = max(band * foam * (0.5 + 0.5 * smoothstep(width, 0.0, d)), under * foam) * strength;
	ALBEDO = vec3(0.9, 0.95, 0.97);
	ALPHA = clamp(a, 0.0, 0.85);
}
