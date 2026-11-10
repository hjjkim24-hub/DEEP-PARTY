shader_type spatial;
// 바다 밑 모래 바닥: 모래 결, 물결무늬, 비탈은 바위, 깊은 곳은 어둡게, 일렁이는 물빛
uniform vec3 sand_a : source_color = vec3(0.62, 0.59, 0.47);
uniform vec3 sand_b : source_color = vec3(0.44, 0.5, 0.41);
uniform vec3 rock_c : source_color = vec3(0.46, 0.47, 0.44);
uniform float caustic_strength = 0.28;
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
	float rip = sin(p.y * 2.4 + p.x * 0.7 + fbm(p * 0.25) * 7.0);
	c *= 0.92 + 0.08 * rip;
	c *= 0.9 + 0.2 * noise(p * 6.0);
	float slope = 1.0 - wnorm.y;
	c = mix(c, rock_c * (0.75 + 0.5 * fbm(p * 0.9)), smoothstep(0.22, 0.5, slope));
	c *= 1.0 - 0.55 * smoothstep(-0.5, -5.0, wpos.y);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	float t = TIME * 0.5;
	float cs = caustic(p * 0.35, t) + 0.6 * caustic(p * 0.6 + 3.1, t * 1.3);
	EMISSION = vec3(0.35, 0.62, 0.52) * cs * caustic_strength * clamp(wnorm.y, 0.0, 1.0) * (1.0 - smoothstep(-1.0, -4.0, wpos.y));
}
