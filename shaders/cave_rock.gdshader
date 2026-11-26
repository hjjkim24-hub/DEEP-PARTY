shader_type spatial;
// 바닷가 동굴 바위: 큰 바위 덩어리 · 지층 결 · 거친 알갱이 · 철분 얼룩 · 물가 쪽은 젖어 번들번들 + 해초 띠
// · 위를 향한 면엔 옅은 이끼 · 벽을 타고 흐른 물 자국 · 발광 이끼 점. 무늬는 세계 좌표 기준이라 이음매 없음.
// 최적화: 높이는 한 번만 구하고 범프는 화면 미분(dFdx/dFdy)으로, 보로노이도 한 번만.
render_mode cull_back, specular_schlick_ggx;

uniform vec3 base_col : source_color = vec3(0.36, 0.33, 0.3);
uniform vec3 dark_col : source_color = vec3(0.16, 0.15, 0.14);
uniform vec3 moss_col : source_color = vec3(0.16, 0.24, 0.12);
uniform vec3 algae_col : source_color = vec3(0.06, 0.16, 0.09);
uniform float water_y = -1.3;
uniform float wet_h = 1.2;
uniform float moss = 0.4;
uniform float drip = 0.5;
uniform float glow = 0.0;

varying vec3 wp;
varying vec3 wn;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
		mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
		mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float v = 0.5 * noise(p);
	p = p * 2.07 + vec3(3.1, 1.7, 5.3);
	v += 0.25 * noise(p);
	p = p * 2.07 + vec3(3.1, 1.7, 5.3);
	v += 0.125 * noise(p);
	return v / 0.875;
}

float fbm2(vec3 p) {
	return (0.5 * noise(p) + 0.25 * noise(p * 2.07 + vec3(3.1, 1.7, 5.3))) / 0.75;
}

// 3D 보로노이 (2x2x2 이웃만 → 8칸): x = 가까운 점까지, y = 경계까지, z = 조각 번호
vec3 voro(vec3 p) {
	vec3 i = floor(p - 0.5);
	vec3 f = p - i;
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int z = 0; z <= 1; z++) {
		for (int y = 0; y <= 1; y++) {
			for (int x = 0; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = vec3(hash(i + g), hash(i + g + 11.7), hash(i + g + 23.1)) * 0.8 + 0.1;
				float d = length(g + o - f);
				if (d < d1) {
					d2 = d1;
					d1 = d;
					id = hash(i + g + 5.3);
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec3(d1, d2 - d1, id);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = wp;
	vec3 n = normalize(wn);
	// 공통 노이즈 (한 번씩만)
	float warp = fbm2(p * 0.5);
	vec3 v = voro(p * vec3(0.45, 0.8, 0.45) + warp * 1.6);
	float lumps = fbm3(p * 1.3);
	float fine = fbm2(p * 6.0);
	float strata = sin(p.y * 4.0 + warp * 9.0) * 0.5 + 0.5;
	float chunk = smoothstep(0.0, 0.25, v.y);
	float h0 = strata * 0.2 + lumps * 0.4 + fine * 0.3 + chunk * 0.2 + v.z * 0.08;
	// 범프: 화면 미분으로 표면 기울기 (높이를 다시 구하지 않음)
	vec3 dpx = dFdx(p);
	vec3 dpy = dFdy(p);
	float dhx = dFdx(h0);
	float dhy = dFdy(h0);
	vec3 r1 = cross(dpy, n);
	vec3 r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	vec3 nw = normalize(abs(det) * n - grad * 0.11);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// 색
	float tone = mix(0.88, 1.1, v.z);
	vec3 c = base_col * tone;
	float masks = fbm2(p * 0.6 + 13.0);
	c = mix(c, dark_col, smoothstep(0.05, 0.0, v.y) * 0.55 * smoothstep(0.45, 0.65, masks));   // 바위 덩어리 사이 금 (군데군데)
	c = mix(c, dark_col, smoothstep(0.35, 0.15, h0) * 0.45);    // 움푹 팬 곳 그늘
	c *= mix(0.82, 1.12, fbm2(p * 14.0));                       // 거친 알갱이
	c *= mix(0.9, 1.08, lumps);
	float stain = fbm2(p * 0.35 + 7.0);
	c = mix(c, c * vec3(1.12, 0.95, 0.8), smoothstep(0.55, 0.8, stain) * 0.6);   // 철분 얼룩
	c = mix(c, c * vec3(0.85, 0.92, 1.0), smoothstep(0.6, 0.85, 1.0 - stain) * 0.4);
	float up = clamp(nw.y, 0.0, 1.0);
	c = mix(c, moss_col, smoothstep(0.6, 0.95, up) * smoothstep(0.45, 0.7, masks) * moss);
	// 물가: 젖음 + 해초 띠 · 벽을 타고 흐른 물 자국
	float above = p.y - water_y;
	float wet = 1.0 - smoothstep(0.0, wet_h, above);
	float streak = smoothstep(0.62, 0.8, fbm2(vec3(p.x * 3.0, p.y * 0.25, p.z * 3.0))) * drip * (1.0 - up);
	wet = max(wet, streak);
	float band = smoothstep(0.55, 0.0, abs(above - 0.15)) * smoothstep(0.35, 0.6, fine);
	c = mix(c, algae_col, clamp(band, 0.0, 1.0) * 0.85);
	c *= mix(1.0, 0.55, wet);
	ALBEDO = c;
	ROUGHNESS = mix(mix(0.82, 0.6, lumps), 0.12, wet);
	SPECULAR = mix(0.35, 0.6, wet);
	if (glow > 0.0) {
		vec3 cell = floor(p * 9.0);
		float r = hash(cell);
		vec3 fp = fract(p * 9.0) - 0.5;
		float dot_ = smoothstep(0.18, 0.0, length(fp)) * step(0.985, r);
		EMISSION = vec3(0.2, 0.9, 0.75) * dot_ * glow * (0.6 + 0.4 * sin(TIME * 1.5 + r * 30.0));
	}
}
