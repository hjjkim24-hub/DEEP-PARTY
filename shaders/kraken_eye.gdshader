shader_type spatial;
// 문어 눈: 눈두덩에 깊이 묻혀 앞쪽만 보임. 금빛 홍채(방사형 결 · 얼룩) + 가로로 긴 동공 + 촉촉한 막. 스스로 빛나지 않음
// 눈알 구의 로컬 +Z 가 정면
render_mode specular_schlick_ggx;
varying vec3 lp;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	lp = normalize(VERTEX);
}

void fragment() {
	vec2 p = lp.xy;
	float front = smoothstep(-0.1, 0.3, lp.z);
	float r = length(p);
	float ang = atan(p.y, p.x);
	// 동공: 가로로 긴 둥근 직사각형 (가운데가 살짝 더 두꺼움)
	vec2 q = abs(p) - vec2(0.36, 0.05 + 0.04 * (1.0 - abs(p.x) / 0.4));
	float pd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.06;
	float pupil = smoothstep(0.015, -0.015, pd);
	float ring = smoothstep(0.12, 0.0, pd) * (1.0 - pupil);       // 동공 둘레 어두운 테
	// 홍채: 금빛~구릿빛, 방사형 섬유 + 얼룩
	float fib = n2(vec2(ang * 30.0, r * 4.0)) * 0.6 + n2(vec2(ang * 80.0, r * 9.0)) * 0.4;
	float blot = n2(p * 9.0);
	vec3 iris = mix(vec3(0.55, 0.36, 0.06), vec3(0.92, 0.74, 0.22), fib);
	iris = mix(iris, vec3(0.35, 0.42, 0.08), smoothstep(0.55, 0.8, blot) * 0.6);
	iris *= 1.0 - ring * 0.65;
	iris *= mix(1.0, 0.25, smoothstep(0.78, 0.98, r));           // 가장자리로 어두워짐
	vec3 sclera = vec3(0.1, 0.13, 0.07);
	vec3 col = mix(sclera, iris, front);
	col = mix(col, vec3(0.008, 0.01, 0.008), pupil * front);
	ALBEDO = col;
	ROUGHNESS = 0.05;
	SPECULAR = 0.7;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.03;
}
