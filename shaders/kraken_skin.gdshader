shader_type spatial;
// 크라켄 피부: 등은 짙은 자줏빛 붉은색에 얼룩 반점, 배(빨판 쪽)는 연한 살구색,
// 젖어서 번들거림(낮은 거칠기 + 가장자리 반사), 미세한 주름 노멀
uniform vec3 back_color : source_color = vec3(0.1, 0.24, 0.07);
uniform vec3 spot_color : source_color = vec3(0.02, 0.07, 0.03);
uniform vec3 belly_color : source_color = vec3(0.58, 0.72, 0.28);
uniform float glow = 0.0;          // 공격 직전 붉게 달아오름
uniform float rough_min = 0.22;
uniform float rough_max = 0.4;
uniform float scale = 1.0;         // 무늬 크기 (큰 몸통은 작게)
uniform vec3 bio_color : source_color = vec3(0.55, 1.0, 0.15);   // 독이 차오른 반점 (스스로 빛남)
uniform float bio = 1.0;
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
	vec3 q = lpos * scale;
	float n1 = noise(q * 7.0);
	float n2 = noise(q * 22.0);
	float n3 = noise(q * 55.0);
	float spots = smoothstep(0.6, 0.7, noise(q * 4.5 + 3.1));
	float mottle = smoothstep(0.35, 0.75, noise(q * 2.2 + 7.0));
	vec3 back = mix(back_color, spot_color, spots * 0.8 + mottle * 0.35) * (0.75 + 0.35 * n1);
	back = mix(back, back * vec3(1.15, 0.85, 0.9), smoothstep(0.7, 0.9, n2) * 0.5);   // 핏줄 같은 얼룩
	vec3 c = mix(back, belly_color * (0.9 + 0.15 * n1), belly);
	// 주름 (가로 줄) → 노멀 흔들기
	float wr = sin(q.y * 60.0 + n1 * 3.0);
	// 오돌토돌한 돌기(피부 유두) + 주름
	vec3 bump = vec3(n3 - 0.5, wr * 0.12 + (n2 - 0.5) * 0.25, noise(q * 55.0 + 9.0) - 0.5);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump * 0.35, 0.0)).xyz);
	ALBEDO = c * (0.92 + 0.08 * n3);
	ROUGHNESS = mix(rough_min, rough_max, n2);
	SPECULAR = 0.5;
	RIM = 0.3;
	RIM_TINT = 0.4;
	SSS_STRENGTH = 0.35;
	// 독 반점: 등 쪽 둥근 반점이 숨 쉬듯 천천히 빛남
	float dots = smoothstep(0.78, 0.84, noise(q * 9.0 + 17.0)) * (1.0 - belly);
	float breathe = 0.55 + 0.45 * sin(TIME * 1.6 + n1 * 6.0);
	ALBEDO = mix(ALBEDO, bio_color * 0.6, dots * 0.7);
	EMISSION = bio_color * dots * breathe * bio * 1.4 + vec3(0.6, 1.0, 0.2) * glow * (0.4 + 0.6 * (1.0 - belly));
}
