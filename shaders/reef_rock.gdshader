shader_type spatial;
// 바위: 얼룩진 돌 + 위쪽엔 이끼, 일렁이는 물빛
uniform vec3 rock_color : source_color = vec3(0.5, 0.5, 0.46);
uniform vec3 moss_color : source_color = vec3(0.27, 0.46, 0.24);
uniform float moss = 1.0;
varying vec3 wpos;
varying vec3 wn;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float caustic(vec2 p, float t) {
	float a = sin(p.x * 3.1 + sin(p.y * 2.3 + t) * 1.7 + t);
	float b = sin(p.y * 3.7 + sin(p.x * 1.9 - t * 1.3) * 1.5 - t * 0.8);
	return pow(max(a * b, 0.0), 2.5);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = noise(wpos * 1.6) * 0.6 + noise(wpos * 4.3) * 0.4;
	vec3 c = rock_color * (0.72 + 0.5 * n);
	float m = smoothstep(0.45, 0.8, wn.y + (n - 0.5) * 0.5) * moss;
	c = mix(c, moss_color * (0.8 + 0.4 * n), m);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	EMISSION = vec3(0.35, 0.62, 0.52) * caustic(wpos.xz * 0.35, TIME * 0.5) * 0.12 * clamp(wn.y, 0.0, 1.0);
}
