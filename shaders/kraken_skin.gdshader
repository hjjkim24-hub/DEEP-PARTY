shader_type spatial;
// 크라켄 피부: 등은 짙은 자줏빛 붉은색에 얼룩 반점, 배(빨판 쪽)는 연한 살구색,
// 젖어서 번들거림(낮은 거칠기 + 가장자리 반사), 미세한 주름 노멀
uniform vec3 back_color : source_color = vec3(0.42, 0.07, 0.16);
uniform vec3 spot_color : source_color = vec3(0.2, 0.02, 0.07);
uniform vec3 belly_color : source_color = vec3(0.84, 0.5, 0.48);
uniform float glow = 0.0;          // 공격 직전 붉게 달아오름
varying vec3 lpos;
varying vec3 lnrm;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}

void fragment() {
	// 배 쪽 = 모델 기준 +Z (빨판이 붙는 쪽)
	float belly = smoothstep(0.35, 0.85, lnrm.z);
	float n1 = noise(lpos * 7.0);
	float n2 = noise(lpos * 22.0);
	float spots = smoothstep(0.62, 0.7, noise(lpos * 4.5 + 3.1));
	vec3 back = mix(back_color, spot_color, spots * 0.8) * (0.8 + 0.35 * n1);
	vec3 c = mix(back, belly_color * (0.9 + 0.15 * n1), belly);
	// 주름 (가로 줄) → 노멀 흔들기
	float wr = sin(lpos.y * 60.0 + n1 * 3.0);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(0.0, wr * 0.12 + (n2 - 0.5) * 0.2, 0.0, 0.0)).xyz);
	ALBEDO = c;
	ROUGHNESS = mix(0.18, 0.32, n2);
	SPECULAR = 0.7;
	RIM = 0.5;
	RIM_TINT = 0.4;
	SSS_STRENGTH = 0.35;
	EMISSION = vec3(1.0, 0.15, 0.1) * glow * (0.4 + 0.6 * (1.0 - belly));
}
