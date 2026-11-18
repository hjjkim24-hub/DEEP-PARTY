shader_type spatial;
// 미니게임 위험 표시: 진한 붉은 바탕 + 밝은 테두리 + 안쪽으로 조여 드는 물결 (밝은 바닥 위에서도 잘 보이게 섞어 그림)
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 col : source_color = vec3(0.95, 0.08, 0.05);
uniform float strength = 1.0;
uniform float aspect = 1.0;     // 띠 모양이면 길이/폭 (물결 간격을 맞춤)

void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	float r = length(d);
	float edge = smoothstep(1.0, 0.9, r) * smoothstep(0.72, 0.9, r);
	float fill = smoothstep(1.0, 0.85, r);
	float wave = fract(r * 2.5 * max(aspect, 1.0) * 0.5 + TIME * 1.4);
	float rings = smoothstep(0.0, 0.1, wave) * smoothstep(0.4, 0.1, wave) * fill;
	float pulse = 0.75 + 0.25 * sin(TIME * 9.0);
	vec3 c = mix(col * 0.75, vec3(1.0, 0.55, 0.4), edge * 0.7 + rings * 0.35);
	ALBEDO = c;
	ALPHA = clamp((fill * 0.38 + edge * 0.9 + rings * 0.25) * pulse * strength, 0.0, 1.0);
}
