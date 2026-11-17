shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// 배 아래로 끝없이 깔린 구름 바다: 달빛 받은 뭉게구름 꼭대기 · 그늘진 골 · 배가 지나가는 쪽으로 흘러감

uniform vec3 top_col : source_color = vec3(0.62, 0.68, 0.92);
uniform vec3 shade_col : source_color = vec3(0.07, 0.08, 0.2);
uniform vec3 far_col : source_color = vec3(0.10, 0.09, 0.21);
uniform vec2 flow = vec2(-7.0, 0.6);
uniform float scale = 0.012;
uniform float cover = 0.45;
uniform float opacity = 1.0;
uniform vec3 moon = vec3(-0.45, 0.6, 0.65);
uniform vec3 center = vec3(0.0);
uniform float fade_far = 700.0;

varying vec3 wpos;

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
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 6; i++) {
		s += a * n2(p);
		p = r * p * 2.02;
		a *= 0.5;
	}
	return s;
}
float dens(vec2 p) {
	// 큰 덩어리 + 뭉게뭉게한 결 (꼭대기가 둥글게)
	float big = fbm(p * 0.35);
	float d = fbm(p + vec2(big * 2.0));
	return smoothstep(cover, cover + 0.35, d * 0.75 + big * 0.45);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (wpos.xz - flow * TIME) * scale;
	float e = 0.6;
	float c = dens(p);
	float cx = dens(p + vec2(e * scale * 10.0, 0.0));
	float cz = dens(p + vec2(0.0, e * scale * 10.0));
	vec3 n = normalize(vec3((c - cx) * 3.0, 1.0, (c - cz) * 3.0));
	float lit = clamp(dot(n, normalize(moon)) * 0.6 + 0.4, 0.0, 1.0);
	vec3 col = mix(shade_col, top_col, pow(c, 0.7) * lit);
	// 뭉게구름 테두리에 달빛이 살짝 번짐
	col += top_col * 0.25 * smoothstep(0.2, 0.5, c) * (1.0 - smoothstep(0.5, 0.9, c)) * lit;
	float dist = length(wpos.xz - center.xz);
	float far = smoothstep(fade_far * 0.25, fade_far, dist);
	col = mix(col, far_col, far);
	ALBEDO = col;
	ALPHA = clamp(c * 1.25, 0.0, 1.0) * opacity * (1.0 - smoothstep(fade_far * 0.8, fade_far, dist) * 0.0);
}
