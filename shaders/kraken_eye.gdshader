shader_type spatial;
// 문어 눈: 금빛 홍채(방사형 결) + 가로로 긴 직사각 동공 + 촉촉한 막. 스스로 빛나지 않음
// 눈알 구의 로컬 +Z 가 정면
render_mode specular_schlick_ggx;
varying vec3 lp;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	lp = normalize(VERTEX);
}

void fragment() {
	vec2 p = lp.xy;                 // 정면에서 본 좌표 (-1..1)
	float front = smoothstep(0.0, 0.4, lp.z);
	float r = length(p);
	float ang = atan(p.y, p.x);
	// 홍채: 금빛 + 방사형 결 + 바깥 어두운 테
	float streak = 0.5 + 0.5 * sin(ang * 40.0 + h(vec2(floor(ang * 12.0), 1.0)) * 6.0);
	vec3 iris = mix(vec3(0.75, 0.52, 0.08), vec3(0.95, 0.8, 0.25), streak * 0.6);
	iris *= mix(1.0, 0.35, smoothstep(0.55, 0.72, r));
	// 동공: 가로로 긴 둥근 직사각형
	vec2 q = abs(p) - vec2(0.32, 0.06);
	float pd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.05;
	float pupil = smoothstep(0.02, -0.02, pd);
	vec3 sclera = vec3(0.12, 0.16, 0.1);
	vec3 col = mix(sclera, iris, front * smoothstep(0.78, 0.7, r));
	col = mix(col, vec3(0.01), pupil * front);
	ALBEDO = col;
	ROUGHNESS = 0.03;
	SPECULAR = 0.9;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.02;
	EMISSION = iris * front * 0.04;
}
