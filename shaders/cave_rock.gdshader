shader_type spatial;
// 바닷가 동굴 바위: 층층이 쌓인 지층 결 · 갈라진 틈 · 색이 다른 광물 얼룩 · 물가 쪽은 젖어 번들번들 + 짙은 이끼 띠
// · 위를 향한 면엔 옅은 이끼. 무늬는 세계 좌표 기준이라 어떤 모양에도 이음매 없이 입혀짐.
render_mode cull_back, specular_schlick_ggx;

uniform vec3 base_col : source_color = vec3(0.36, 0.33, 0.3);
uniform vec3 dark_col : source_color = vec3(0.16, 0.15, 0.14);
uniform vec3 moss_col : source_color = vec3(0.16, 0.24, 0.12);
uniform vec3 algae_col : source_color = vec3(0.06, 0.16, 0.09);
uniform float water_y = -1.3;      // 이 높이 근처가 물가 (젖음 · 이끼 띠)
uniform float wet_h = 1.2;         // 물가에서 이만큼 위까지 젖음
uniform float moss = 0.4;
uniform float drip = 0.5;          // 벽을 타고 흐른 물 자국
uniform float glow = 0.0;          // 발광 이끼 점

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

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec3(3.1, 1.7, 5.3);
		a *= 0.5;
	}
	return v;
}

// 3D 보로노이: x = 가장 가까운 점까지, y = 경계까지, z = 조각 번호
vec3 voro(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = vec3(hash(i + g), hash(i + g + 11.7), hash(i + g + 23.1));
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

// 높이장: 바위 조각(보로노이) + 지층 결 + 거친 결
float rock_h(vec3 p) {
	float strata = sin(p.y * 4.0 + fbm(p * 0.45) * 9.0 + fbm(p * 1.3) * 2.0) * 0.5 + 0.5;
	float lumps = fbm(p * 1.3);
	float fine = fbm(p * 6.0);
	vec3 v = voro(p * vec3(0.45, 0.8, 0.45) + vec3(fbm(p * 0.5), fbm(p * 0.5 + 3.0), fbm(p * 0.5 + 6.0)) * 1.6);
	float chunk = smoothstep(0.0, 0.25, v.y);              // 큰 바위 덩어리 경계는 살짝 움푹
	return strata * 0.2 + lumps * 0.4 + fine * 0.3 + chunk * 0.2 + v.z * 0.08;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = wp;
	// 범프: 높이장의 기울기로 노멀을 비틂
	float e = 0.02;
	float h0 = rock_h(p);
	vec3 g = vec3(rock_h(p + vec3(e, 0, 0)) - h0, rock_h(p + vec3(0, e, 0)) - h0, rock_h(p + vec3(0, 0, e)) - h0) / e;
	g -= wn * dot(g, wn);
	vec3 nw = normalize(wn - g * 0.11);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// 색: 지층마다 살짝 다른 색 · 얼룩 · 틈은 어둡게
	float layer = fbm(vec3(p.x * 0.22, p.y * 1.4, p.z * 0.22) + fbm(p * 0.5) * 1.5);
	float stain = fbm(p * 0.35 + 7.0);
	vec3 v = voro(p * vec3(0.45, 0.8, 0.45) + vec3(fbm(p * 0.5), fbm(p * 0.5 + 3.0), fbm(p * 0.5 + 6.0)) * 1.6);
	float tone = mix(0.88, 1.1, v.z);                     // 조각마다 살짝 다른 톤
	vec3 c = base_col * tone;
	float fmask = smoothstep(0.45, 0.65, fbm(p * 0.6 + 13.0));   // 금은 군데군데만
	c = mix(c, dark_col, smoothstep(0.05, 0.0, v.y) * 0.55 * fmask);   // 바위 덩어리 사이 금
	c = mix(c, dark_col, smoothstep(0.35, 0.15, h0) * 0.45);   // 움푹 팬 곳 그늘
	float grain = fbm(p * 14.0);
	c *= mix(0.82, 1.12, grain);                           // 거친 결 (작은 알갱이)
	c *= mix(0.9, 1.08, layer);
	c = mix(c, c * vec3(1.12, 0.95, 0.8), smoothstep(0.55, 0.8, stain) * 0.6);   // 철분 얼룩 (붉은 기)
	c = mix(c, c * vec3(0.85, 0.92, 1.0), smoothstep(0.6, 0.85, 1.0 - stain) * 0.4);
	// 가는 금: 드문드문 (다른 노이즈로 가려서 군데군데만)
	float crack = smoothstep(0.012, 0.0, abs(fbm(p * 0.9 + 2.0) - 0.5)) * smoothstep(0.55, 0.7, fbm(p * 0.4 + 9.0)) * 0.45;
	c *= 1.0 - crack;
	// 구멍 · 움푹 팬 곳은 어둡게 (높이장 낮은 곳)
	c *= mix(0.8, 1.04, smoothstep(0.25, 0.65, h0));
	// 위를 향한 면: 옅은 이끼
	float up = clamp(nw.y, 0.0, 1.0);
	c = mix(c, moss_col, smoothstep(0.6, 0.95, up) * smoothstep(0.45, 0.7, fbm(p * 0.9)) * moss);
	// 물가: 젖음 (짙고 번들) + 이끼 띠 (물 바로 위)
	float above = p.y - water_y;
	float wet = 1.0 - smoothstep(0.0, wet_h, above);
	// 벽을 타고 흐른 물 자국 (세로 줄무늬)
	float streak = smoothstep(0.62, 0.8, fbm(vec3(p.x * 3.0, p.y * 0.25, p.z * 3.0))) * drip * (1.0 - up);
	wet = max(wet, streak);
	float band = smoothstep(0.55, 0.0, abs(above - 0.15)) * smoothstep(0.35, 0.6, fbm(p * 2.5 + 4.0));
	c = mix(c, algae_col, clamp(band, 0.0, 1.0) * 0.85);
	c *= mix(1.0, 0.55, wet);
	ALBEDO = c;
	ROUGHNESS = mix(mix(0.82, 0.6, layer), 0.12, wet);
	SPECULAR = mix(0.35, 0.6, wet);
	// 발광 이끼 (청록 점)
	if (glow > 0.0) {
		vec3 cell = floor(p * 9.0);
		float r = hash(cell);
		vec3 fp = fract(p * 9.0) - 0.5;
		float dot_ = smoothstep(0.18, 0.0, length(fp)) * step(0.985, r);
		EMISSION = vec3(0.2, 0.9, 0.75) * dot_ * glow * (0.6 + 0.4 * sin(TIME * 1.5 + r * 30.0));
	}
}
