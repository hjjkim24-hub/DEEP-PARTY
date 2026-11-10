shader_type spatial;
// 뇌산호: 구불구불한 골
uniform vec3 color : source_color = vec3(0.85, 0.75, 0.45);
varying vec3 lpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec2 p = lpos.xz * 2.2 + lpos.y * 1.3;
	float g = sin((noise(p) * 0.7 + noise(p * 2.1) * 0.3) * 30.0);
	float groove = smoothstep(0.55, 1.0, g);
	ALBEDO = mix(color, color * 0.5, groove);
	ROUGHNESS = 0.7;
}
