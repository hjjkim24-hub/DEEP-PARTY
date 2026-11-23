shader_type spatial;
// 미니게임 위험 표시: 진한 붉은 바탕 + 밝은 테두리 + 안쪽으로 조여 드는 물결 (밝은 바닥 위에서도 잘 보이게 섞어 그림)
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 col : source_color = vec3(0.95, 0.08, 0.05);
uniform vec3 edge_col : source_color = vec3(1.0, 0.55, 0.4);   // 테두리 · 물결 색 (먹물 경고는 회색)
uniform float strength = 1.0;
uniform float aspect = 1.0;     // 띠 모양이면 길이/폭 (물결 간격을 맞춤)
uniform bool rect = false;      // 직사각형 (촉수가 눕는 자리): 테두리 + 촉수 끝 쪽으로 흐르는 화살 무늬
uniform vec2 size = vec2(1.0, 1.0);   // 직사각형 실제 크기 (m): x = 폭, y = 길이

void fragment() {
	if (rect) {
		vec2 p = (UV - 0.5) * size;           // 가운데 기준 (m)
		vec2 hd = size * 0.5 - abs(p);        // 테두리까지 거리
		float inside = step(0.0, min(hd.x, hd.y));
		float border = inside * (1.0 - smoothstep(0.06, 0.16, min(hd.x, hd.y)));
		// 뿌리 → 끝 쪽으로 흐르는 꺾쇠 무늬
		float chev = fract((p.y - abs(p.x) * 0.9) * 0.75 + TIME * 1.6);
		float arrows = smoothstep(0.0, 0.08, chev) * smoothstep(0.38, 0.2, chev) * inside;
		float pulse = 0.8 + 0.2 * sin(TIME * 10.0);
		vec3 c = mix(col * 0.8, edge_col, border * 0.8 + arrows * 0.35);
		ALBEDO = c;
		ALPHA = clamp((inside * 0.32 + border * 0.95 + arrows * 0.3) * pulse * strength, 0.0, 1.0);
	} else {
	vec2 d = (UV - 0.5) * 2.0;
	float r = length(d);
	float edge = smoothstep(1.0, 0.9, r) * smoothstep(0.72, 0.9, r);
	float fill = smoothstep(1.0, 0.85, r);
	float wave = fract(r * 2.5 * max(aspect, 1.0) * 0.5 + TIME * 1.4);
	float rings = smoothstep(0.0, 0.1, wave) * smoothstep(0.4, 0.1, wave) * fill;
	float pulse = 0.75 + 0.25 * sin(TIME * 9.0);
	vec3 c = mix(col * 0.75, edge_col, edge * 0.7 + rings * 0.35);
	ALBEDO = c;
	ALPHA = clamp((fill * 0.38 + edge * 0.9 + rings * 0.25) * pulse * strength, 0.0, 1.0);
}
}
