shader_type spatial;
// 해변 모래: 마른 모래(바람 물결무늬 · 조개 부스러기) → 물가로 갈수록 젖어 짙고 번들 → 밀려왔다 빠지는 파도 끝 거품.
// 놀이 구역은 거의 평평하고, 앞(+z)은 바다로 비스듬히 내려가고 뒤(-z)는 모래언덕으로 솟음 (정점에서 높이).
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 dry_col : source_color = vec3(0.74, 0.63, 0.47);
uniform vec3 wet_col : source_color = vec3(0.45, 0.37, 0.27);
uniform float shore_z = 7.2;      // 파도가 닿는 평균 자리
uniform float water_y = -0.32;

varying vec3 wp;
varying float hgt;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return 0.5 * noise(p) + 0.25 * noise(p * 2.1 + 3.7) + 0.125 * noise(p * 4.3 + 9.1);
}

float height_at(vec2 p) {
	float down = -smoothstep(4.8, 10.0, p.y) * 1.7;                 // 바다 쪽으로 내려감
	float dune = smoothstep(-6.8, -11.0, p.y) * (0.9 + 0.7 * fbm(p * 0.18));   // 뒤쪽 모래언덕
	float side = smoothstep(10.8, 14.0, abs(p.x)) * 0.5 * fbm(p * 0.3 + 2.0);
	float bump = (fbm(p * 0.35) - 0.5) * 0.08 * (1.0 - smoothstep(4.5, 6.5, p.y));
	return down + dune + side + bump;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = height_at(w.xz);
	VERTEX.y += h;
	// 경사에 맞춘 노멀
	float e = 0.25;
	float hx = height_at(w.xz + vec2(e, 0.0)) - height_at(w.xz - vec2(e, 0.0));
	float hz = height_at(w.xz + vec2(0.0, e)) - height_at(w.xz - vec2(0.0, e));
	NORMAL = normalize(vec3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)));
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hgt = h;
}

void fragment() {
	vec2 uv = wp.xz * 0.21;
	vec3 a = texture(sand_albedo, uv).rgb;
	vec3 a2 = texture(sand_albedo, uv * 0.29 + 0.41).rgb;
	float lum = dot(mix(a, a2, 0.45), vec3(0.333));
	// 바람이 만든 물결무늬 (마른 모래에만)
	float rip = sin(wp.x * 5.2 + wp.z * 1.9 + fbm(wp.xz * 0.7) * 6.0) * 0.5 + 0.5;
	// 밀려왔다 빠지는 파도: 물가선이 앞뒤로 오감
	float t = TIME;
	float swash = shore_z + sin(t * 0.55) * 0.9 + sin(t * 0.21 + 1.3) * 0.4 + (fbm(vec2(wp.x * 0.35, t * 0.1)) - 0.5) * 1.4;
	float wet = smoothstep(shore_z - 2.6, shore_z - 0.3, wp.z);                    // 젖은 띠 (늘 축축)
	wet = max(wet, smoothstep(swash - 0.15, swash + 0.25, wp.z));                  // 파도가 방금 덮은 곳
	float puddle = smoothstep(0.62, 0.7, fbm(wp.xz * 0.5 + 7.0)) * smoothstep(shore_z - 3.2, shore_z - 1.0, wp.z);
	wet = clamp(wet + puddle * 0.6, 0.0, 1.0);
	vec3 c = mix(dry_col, wet_col, wet) * mix(0.82, 1.12, lum);
	c *= mix(1.0, mix(0.93, 1.04, rip), (1.0 - wet) * 0.7);
	// 조개 부스러기 · 작은 돌 점
	float speck = step(0.985, hash(floor(wp.xz * 34.0)));
	c = mix(c, vec3(0.97, 0.94, 0.9), speck * 0.6 * (1.0 - wet));
	float dark_speck = step(0.992, hash(floor(wp.xz * 41.0) + 3.0));
	c = mix(c, vec3(0.3, 0.28, 0.26), dark_speck * 0.5);
	// 파도 끝 거품 (가장자리 레이스 무늬)
	float edge = smoothstep(0.55, 0.0, abs(wp.z - swash)) ;
	float f = texture(foam_tex, wp.xz * 0.33 + vec2(t * 0.02, t * 0.05)).r;
	float lace = smoothstep(0.35, 0.7, f) * edge;
	float behind = smoothstep(swash, swash + 1.2, wp.z) * smoothstep(0.45, 0.8, f) * 0.5;
	c = mix(c, vec3(0.95, 0.97, 0.98), clamp(lace + behind, 0.0, 0.9));
	// 뒤쪽 언덕 마른 풀빛 기운
	c = mix(c, c * vec3(0.92, 0.96, 0.82), smoothstep(-7.0, -10.0, wp.z) * 0.5);
	ALBEDO = c;
	NORMAL_MAP = texture(sand_normal, uv).rgb;
	NORMAL_MAP_DEPTH = mix(0.9, 0.35, wet);
	ROUGHNESS = mix(0.95, 0.22, wet);
	SPECULAR = mix(0.25, 0.6, wet);
}
