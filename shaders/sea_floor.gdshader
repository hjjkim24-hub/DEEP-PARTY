shader_type spatial;
// 바다 밑 모래 바닥: 모래 결, 물결무늬, 비탈은 바위, 깊은 곳은 어둡게, 일렁이는 물빛
uniform vec3 sand_a : source_color = vec3(0.6, 0.58, 0.47);
uniform vec3 sand_b : source_color = vec3(0.43, 0.49, 0.4);
uniform vec3 rock_c : source_color = vec3(0.38, 0.4, 0.38);
uniform float caustic_strength = 0.34;
// 길 자국(R) · 칸 둘레 그늘(G)
uniform sampler2D path_mask : filter_linear, repeat_disable;
uniform vec4 board_rect = vec4(-18.0, -16.0, 36.0, 32.0);
varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
// 자갈 무늬: 가장 가까운 점까지 거리 + 그 점의 번호
vec3 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.3)) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; id = i + g; }
			else if (d < d2) { d2 = d; }
		}
	}
	return vec3(d2 - d1, hash(id), d1);
}
float caustic(vec2 p, float t) {
	float a = sin(p.x * 3.1 + sin(p.y * 2.3 + t) * 1.7 + t);
	float b = sin(p.y * 3.7 + sin(p.x * 1.9 - t * 1.3) * 1.5 - t * 0.8);
	return pow(max(a * b, 0.0), 2.5);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	float n = fbm(p * 0.12);
	vec3 c = mix(sand_a, sand_b, smoothstep(0.3, 0.7, n));
	// 밝은 모래 자리, 초록 이끼 얼룩
	c = mix(c, vec3(0.8, 0.76, 0.62), smoothstep(0.55, 0.75, fbm(p * 0.07 + 4.0)) * 0.6);
	c = mix(c, vec3(0.32, 0.46, 0.3), smoothstep(0.62, 0.8, fbm(p * 0.1 - 7.0)) * 0.55);
	float rip = sin(p.y * 2.4 + p.x * 0.7 + fbm(p * 0.25) * 7.0);
	c *= 0.92 + 0.08 * rip;
	c *= 0.9 + 0.2 * noise(p * 6.0);
	// 다져진 길 + 군데군데 박힌 자갈
	vec2 m = texture(path_mask, (p - board_rect.xy) / board_rect.zw).rg;
	float edge = (fbm(p * 1.4 + 9.0) - 0.5) * 0.45;
	float path = smoothstep(0.3, 0.62, m.r + edge);
	vec3 cel = cells(p * 2.6);
	float stones = smoothstep(0.04, 0.12, cel.x) * step(0.35, cel.y) * smoothstep(0.55, 0.85, m.r + edge * 0.5);
	vec3 trod = mix(vec3(0.5, 0.47, 0.38), vec3(0.44, 0.43, 0.36), noise(p * 3.0));
	vec3 stone_c = mix(vec3(0.56, 0.54, 0.48), vec3(0.66, 0.6, 0.5), cel.y) * (0.85 + 0.15 * noise(p * 9.0));
	c = mix(c, trod, path * 0.8);
	c = mix(c, stone_c, stones * 0.9);
	c *= 1.0 - 0.18 * path * (1.0 - stones) * smoothstep(0.08, 0.0, cel.x);
	// 칸 둘레 접지 그늘
	c *= 1.0 - 0.38 * m.g;
	// 비탈은 결이 있는 바위
	float slope = 1.0 - wnorm.y;
	float strata = 0.82 + 0.18 * sin(wpos.y * 5.5 + fbm(p * 0.6) * 5.0);
	vec3 rock = rock_c * (0.7 + 0.45 * fbm(p * 0.9 + wpos.y * 0.3)) * strata;
	rock = mix(rock, vec3(0.3, 0.42, 0.32), smoothstep(0.55, 0.8, fbm(p * 0.5 + wpos.y * 0.4)) * 0.5);
	c = mix(c, rock, smoothstep(0.2, 0.45, slope));
	c *= 1.0 - 0.55 * smoothstep(-0.5, -5.0, wpos.y);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	// 모래알 반짝
	vec2 cell = floor(p * 14.0);
	float glint = step(0.993, hash(cell)) * (0.5 + 0.5 * sin(TIME * 3.0 + hash(cell + 3.1) * 40.0));
	float t = TIME * 0.5;
	float cs = caustic(p * 0.35, t) + 0.6 * caustic(p * 0.6 + 3.1, t * 1.3);
	EMISSION = vec3(0.8, 0.95, 0.9) * glint * 0.35 + vec3(0.35, 0.62, 0.52) * cs * caustic_strength * clamp(wnorm.y, 0.0, 1.0) * (1.0 - smoothstep(-1.0, -4.0, wpos.y));
}
