shader_type spatial;
// 바위: 고해상도 바위 결(갈라진 틈 · 광물 알갱이)을 세 방향에서 입힘 + 위쪽엔 이끼, 일렁이는 물빛
uniform vec3 rock_color : source_color = vec3(0.5, 0.5, 0.46);
uniform vec3 moss_color : source_color = vec3(0.27, 0.46, 0.24);
uniform float moss = 1.0;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 2.2;
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
	vec3 w = pow(abs(wn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 q = wpos / tex_scale;
	vec3 tx = texture(rock_tex, q.zy).rgb;
	vec3 ty = texture(rock_tex, q.xz + 0.31).rgb;
	vec3 tz = texture(rock_tex, q.xy + 0.67).rgb;
	vec3 tex = (tx * w.x + ty * w.y + tz * w.z) / vec3(0.49, 0.48, 0.45);
	vec2 nx = texture(rock_nrm, q.zy).xy * 2.0 - 1.0;
	vec2 ny = texture(rock_nrm, q.xz + 0.31).xy * 2.0 - 1.0;
	vec2 nz = texture(rock_nrm, q.xy + 0.67).xy * 2.0 - 1.0;
	vec3 pert = vec3(0.0, nx.y, nx.x) * w.x * sign(wn.x) + vec3(ny.x, 0.0, ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z * sign(wn.z);
	vec3 n3 = normalize(wn + pert * 0.85);
	NORMAL = normalize((VIEW_MATRIX * vec4(n3, 0.0)).xyz);

	float n = noise(wpos * 1.6) * 0.6 + noise(wpos * 4.3) * 0.4;
	vec3 c = rock_color * (0.78 + 0.4 * n) * tex;
	float m = smoothstep(0.45, 0.8, n3.y + (n - 0.5) * 0.6 + (tex.g - 1.0) * 0.4) * moss;
	c = mix(c, moss_color * (0.75 + 0.4 * n) * mix(vec3(1.0), tex, 0.5), m);
	ALBEDO = c;
	ROUGHNESS = mix(0.88, 0.95, m);
	AO = clamp(tex.r * 1.1, 0.4, 1.0);
	AO_LIGHT_AFFECT = 0.3;
	EMISSION = vec3(0.35, 0.62, 0.52) * caustic(wpos.xz * 0.35, TIME * 0.5) * 0.12 * clamp(n3.y, 0.0, 1.0);
}
