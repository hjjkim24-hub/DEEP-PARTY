shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
// 크라켄의 배로 떨어지는 포탈: 소용돌이치는 검붉은 구멍 + 빛나는 테두리

uniform vec3 rim : source_color = vec3(1.0, 0.25, 0.2);
uniform vec3 swirl_col : source_color = vec3(0.55, 0.06, 0.12);
uniform float open = 1.0;
uniform float spin = 1.0;

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

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q) / max(open, 0.001);
	if (r > 1.0) {
		discard;
	}
	float a = atan(q.y, q.x);
	float t = TIME * spin;
	float sw = sin(a * 3.0 + log(r + 0.02) * 7.0 + t * 5.0);
	float sw2 = n2(vec2(a * 2.0 + t * 2.0, log(r + 0.02) * 4.0 - t * 3.0));
	vec3 col = mix(vec3(0.0), swirl_col, smoothstep(-0.2, 1.0, sw) * 0.8 + sw2 * 0.4) * smoothstep(0.0, 0.8, r);
	// 테두리: 밝게 일렁
	float ring = smoothstep(0.72, 0.95, r) * (1.0 - smoothstep(0.95, 1.0, r));
	col += rim * ring * (1.6 + 0.6 * sin(a * 6.0 + t * 7.0));
	col += rim * pow(r, 6.0) * 0.6;
	ALBEDO = col;
	ALPHA = clamp(0.92 * smoothstep(1.0, 0.9, r) + ring, 0.0, 1.0) * smoothstep(0.0, 0.15, open);
}
