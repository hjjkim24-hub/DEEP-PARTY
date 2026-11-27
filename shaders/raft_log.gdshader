shader_type spatial;
// 뗏목 통나무: 세로로 갈라진 거친 나무껍질 · 사람이 밟아 껍질이 벗겨지고 햇볕·소금기에 바랜 윗면(긴 나뭇결)
// · 물에 닿는 아랫부분은 젖어 짙고 번들번들 + 초록 물때 · 이끼 + 물가 따개비 · 잘린 끝은 나이테와 갈라진 금.
// 무늬는 통나무 자신의 좌표(UV: x = 둘레 0~1, y = 길이 m / 끝면은 COLOR.r = 1, UV = 단면 좌표 m)라 뗏목이 기울어도 따라감.
// 젖음만 세계 높이(water_y) 기준.
render_mode cull_back, specular_schlick_ggx;

uniform vec3 bark_col : source_color = vec3(0.27, 0.2, 0.14);
uniform vec3 wood_col : source_color = vec3(0.56, 0.47, 0.36);
uniform vec3 algae_col : source_color = vec3(0.12, 0.2, 0.1);
uniform float radius = 0.4;
uniform float seed = 0.0;
uniform float water_y = 0.0;
uniform float wash = 0.0;      // 파도가 덮친 직후 윗면까지 젖음 (0~1)

varying vec3 wp;
varying vec3 wn;
varying vec3 lp;
varying float cap;

float hash2(vec2 p) {
	p = fract(p * vec2(0.3183099, 0.3678794) + vec2(0.1, 0.7));
	p *= 17.0;
	return fract(p.x * p.y * (p.x + p.y));
}

float noise2(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.5 * noise2(p);
	p = p * 2.03 + vec2(1.7, 9.2);
	v += 0.25 * noise2(p);
	p = p * 2.03 + vec2(1.7, 9.2);
	v += 0.125 * noise2(p);
	return v / 0.875;
}

// 2D 보로노이: x = 가까운 점까지, y = 점 번호
vec2 voro(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash2(i + g), hash2(i + g + 7.3));
			float d = length(g + o - f);
			if (d < d1) {
				d1 = d;
				id = hash2(i + g + 3.1);
			}
		}
	}
	return vec2(d1, id);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lp = VERTEX;
	cap = COLOR.r;
}

void fragment() {
	vec3 n = normalize(wn);
	vec3 c;
	float h0;
	float rough;
	float sd = seed * 13.7;
	if (cap > 0.5) {
		// 잘린 끝: 나이테 · 가운데로 갈라진 금 · 바깥 껍질 테두리 · 회색으로 바램
		vec2 q = UV;
		float rr = length(q);
		float ang = atan(q.y, q.x);
		float wob = fbm(vec2(ang * 2.0 + sd, rr * 3.0)) * 0.03;
		float ring = fract((rr + wob) * 17.0);
		float late = smoothstep(0.55, 0.85, ring);
		c = mix(vec3(0.6, 0.5, 0.37), vec3(0.5, 0.4, 0.28), late);
		c = mix(c, vec3(0.5, 0.48, 0.45), 0.35 + 0.25 * fbm(q * 9.0 + sd));      // 햇볕에 바래 회색빛
		float crack = smoothstep(0.03, 0.0, abs(fract((ang + sd) * 0.95) - 0.5) * rr * 2.5) * smoothstep(0.05, 0.25, rr);
		c *= 1.0 - crack * 0.7;
		float edge = smoothstep(radius * 0.86, radius * 0.94, rr);
		c = mix(c, bark_col * 0.8, edge);
		c = mix(c, vec3(0.35, 0.3, 0.25), smoothstep(0.08, 0.0, rr) * 0.6);   // 심
		h0 = late * 0.2 - crack * 0.5 + edge * 0.3;
		rough = 0.92;
	} else {
		// 몸통: 둘레 좌표(m) u, 길이 v
		float u = UV.x * 6.2831 * radius;
		float v = UV.y;
		// 나무껍질: 세로로 길게 갈라진 골 (길이 방향으로 늘어진 노이즈)
		float b1 = fbm(vec2(u * 7.0 + sd, v * 0.9));
		float ridge = 1.0 - abs(b1 * 2.0 - 1.0);
		float plates = fbm(vec2(u * 3.0 + sd, v * 2.2 + 4.0));
		float bark_h = ridge * 0.6 + plates * 0.4;
		vec3 bark = bark_col * mix(0.45, 1.2, bark_h);
		bark = mix(bark, bark * vec3(0.85, 0.95, 0.85), smoothstep(0.55, 0.8, fbm(vec2(u * 1.3, v * 0.7) + sd)));   // 군데군데 이끼빛
		// 윗면: 밟혀서 껍질이 벗겨진 맨 나무 (가장자리는 너덜너덜하게)
		float up = n.y;
		float worn = smoothstep(0.45, 0.8, up + (fbm(vec2(u * 2.5, v * 1.5) + sd + 2.0) - 0.5) * 0.5);
		float grain = fbm(vec2(u * 34.0 + sd, v * 1.2));
		float grain2 = sin((u * 55.0 + fbm(vec2(u * 3.0, v * 0.6)) * 8.0) ) * 0.5 + 0.5;
		vec3 wood = wood_col * mix(0.78, 1.12, grain) * mix(0.92, 1.05, grain2);
		wood = mix(wood, vec3(0.52, 0.47, 0.41), 0.15 * fbm(vec2(u, v) * 2.0 + sd));     // 소금기 · 햇볕에 바램
		float crack = smoothstep(0.016, 0.0, abs(fbm(vec2(u * 6.0 + sd, v * 0.2)) - 0.5)) * worn;   // 길게 갈라진 금
		wood *= 1.0 - crack * 0.45;
		// 옹이
		float knot = 0.0;
		vec3 knot_c = wood_col;
		if (worn > 0.05) {   // 옹이는 윗면에서만 (계산 아낌)
			vec2 kv = voro(vec2(u * 1.4, v * 0.55) + sd);
			knot = smoothstep(0.16, 0.05, kv.x) * step(0.86, kv.y);
			knot_c = mix(wood_col * 0.45, wood_col * 0.75, smoothstep(0.02, 0.12, kv.x));
		}
		c = mix(bark, wood, worn);
		c = mix(c, knot_c, knot * mix(0.6, 1.0, worn));
		h0 = mix(bark_h * 0.9, grain * 0.15 - crack * 0.4, worn) - knot * 0.2;
		rough = mix(0.97, 0.88, worn);
		// 물가 따개비 (물 높이 근처 · 아랫면)
		float above0 = wp.y - water_y;
		if (above0 < 0.25 && above0 > -0.45 && worn < 0.95) {   // 물가에서만 (계산 아낌)
			vec2 bv = voro(vec2(u * 14.0, v * 14.0) + sd);
			float barn = smoothstep(0.32, 0.18, bv.x) * step(0.55, bv.y) * smoothstep(0.25, 0.0, above0) * smoothstep(-0.45, -0.05, above0) * (1.0 - worn);
			c = mix(c, vec3(0.62, 0.6, 0.55) * mix(0.8, 1.1, bv.y), barn);
			h0 += barn * 0.6;
		}
	}
	// 범프 (화면 미분)
	vec3 dpx = dFdx(wp);
	vec3 dpy = dFdy(wp);
	float dhx = dFdx(h0);
	float dhy = dFdy(h0);
	vec3 r1 = cross(dpy, n);
	vec3 r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	vec3 nw = normalize(abs(det) * n - grad * 0.05);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// 젖음: 물에 잠긴 곳 · 물가 (파도가 철썩이는 높이) · 파도가 덮친 직후 윗면
	float above = wp.y - water_y;
	float wet = 1.0 - smoothstep(-0.02, 0.22 + 0.08 * fbm(wp.xz * 3.0), above);
	wet = max(wet, wash * (0.6 + 0.4 * fbm(wp.xz * 2.0)));
	float slime = smoothstep(0.12, -0.1, above);
	c = mix(c, algae_col * mix(0.7, 1.2, fbm(wp.xz * 5.0 + vec2(wp.y))), slime * 0.8 * (1.0 - cap * 0.5));
	c *= mix(1.0, 0.5, wet);
	ALBEDO = c;
	ROUGHNESS = mix(rough, 0.18, wet);
	SPECULAR = mix(0.12, 0.55, wet);
}
