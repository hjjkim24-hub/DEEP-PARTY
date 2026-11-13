shader_type spatial;
// 크라켄이 노린 칸: 칸 둘레에 번지는 붉은 빛 + 안쪽으로 조여 드는 물결 고리 (바닥에 깔림)
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 1.0;
uniform vec3 col : source_color = vec3(1.0, 0.15, 0.08);

void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	float edge = smoothstep(1.0, 0.8, r) * smoothstep(0.42, 0.8, r);
	float fill = smoothstep(0.85, 0.2, r) * 0.25;
	float wave = fract(r * 2.0 + TIME * 0.9);
	float rings = smoothstep(0.0, 0.08, wave) * smoothstep(0.35, 0.08, wave) * smoothstep(1.0, 0.3, r);
	float pulse = 0.65 + 0.35 * sin(TIME * 4.0);
	float a = (edge * 1.6 + rings * 0.7 + fill) * pulse * strength;
	ALBEDO = col * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
