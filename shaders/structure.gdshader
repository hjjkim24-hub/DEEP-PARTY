shader_type spatial;
// 구조물 · 장식품 재질: 풍화된 돌 결(세 방향) 위에 종류별 무늬를 얹고, 이끼 · 물때 · 일렁이는 물빛을 더함
// kind: 0 통돌, 1 쌓은 돌(줄눈), 2 나무 널, 3 기와, 4 홈 파인 기둥, 5 뼈, 6 벗겨진 칠, 7 산호, 8 토기, 9 녹슨 쇠
render_mode specular_schlick_ggx;
uniform vec3 base : source_color = vec3(0.7, 0.68, 0.6);
uniform int kind = 0;
uniform float rough = 0.85;
uniform float moss = 0.6;
uniform vec3 grain = vec3(0.0, 0.0, 1.0);   // 나뭇결 방향 (로컬)
uniform float caustics = 1.0;     // 물속 빛 무늬 (하늘 위 배에서는 0)
uniform float plank_w = 0.3;                // 널 너비 (0 = 통널 한 장: 틈 없음)
uniform float radial = 0.0;       // > 0: 둥근 벽 · 원뿔 지붕 (값 = 대략의 반지름)
uniform sampler2D det_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D det_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 lp;
varying vec3 ln;
varying vec3 wpos;
varying vec3 wn;
varying float oid;
// 합쳐 그리기(StaticBatcher)용: 물체마다의 로컬 좌표 · 로컬 법선 · 회전을 꼭짓점 CUSTOM 에 담아 옴
uniform bool batched = false;
varying vec3 bx;
varying vec3 by;
varying vec3 bz;      // 물체마다 다른 값 (널마다 색이 조금씩 다르게)

float hash1(float n) { return fract(sin(n * 91.3458) * 47453.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}
float fbm3(vec3 p) {
	return noise3(p) * 0.5 + noise3(p * 2.1 + 3.0) * 0.3 + noise3(p * 4.3 + 7.0) * 0.2;
}
float caustic(vec2 p, float t) {
	float a = sin(p.x * 3.1 + sin(p.y * 2.3 + t) * 1.7 + t);
	float b = sin(p.y * 3.7 + sin(p.x * 1.9 - t * 1.3) * 1.5 - t * 0.8);
	return pow(max(a * b, 0.0), 2.5);
}

void vertex() {
	if (batched) {
		lp = CUSTOM0.xyz;
		oid = CUSTOM0.w;
		bx = CUSTOM1.xyz;
		by = CUSTOM2.xyz;
		bz = CUSTOM3.xyz;
		ln = vec3(CUSTOM1.w, CUSTOM2.w, CUSTOM3.w);
	} else {
		lp = VERTEX;
		ln = NORMAL;
		bx = MODEL_MATRIX[0].xyz;
		by = MODEL_MATRIX[1].xyz;
		bz = MODEL_MATRIX[2].xyz;
		oid = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 nl = normalize(ln);
	vec3 an = abs(nl);
	vec3 w = pow(an, vec3(4.0));
	w /= (w.x + w.y + w.z);
	// 돌 결 (세 방향에서)
	float ts = 0.4;
	vec3 det = texture(det_tex, lp.zy * ts).rgb * w.x + texture(det_tex, lp.xz * ts).rgb * w.y + texture(det_tex, lp.xy * ts).rgb * w.z;
	vec3 nx = texture(det_nrm, lp.zy * ts).rgb * 2.0 - 1.0;
	vec3 ny = texture(det_nrm, lp.xz * ts).rgb * 2.0 - 1.0;
	vec3 nz = texture(det_nrm, lp.xy * ts).rgb * 2.0 - 1.0;
	vec3 bump = vec3(0.0, nx.y, nx.x) * w.x + vec3(ny.x, 0.0, ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z;
	float det_k = 1.0;

	// 면 위 좌표 (u: 가로, v: 세로)
	bool top = an.y > 0.7;
	float ang = atan(lp.x, lp.z);
	vec3 tu = vec3(cos(ang), 0.0, -sin(ang));
	vec2 fc;
	bool rad_on = radial > 0.01 && (kind == 3 || !top);    // 둥근 벽의 윗면은 평면 무늬로
	if (rad_on) {
		fc = vec2(ang * radial, lp.y);
	} else if (top) {
		fc = lp.xz;
	} else {
		fc = vec2(an.x > an.z ? lp.z : lp.x, lp.y);
	}

	vec3 c = base;
	float groove = 0.0;     // 줄눈 · 틈 (어둡고 이끼가 잘 낌)
	float tint = 0.0;       // 조각마다 다른 밝기
	float shade = 1.0;
	float r = rough;
	float moss_k = moss;
	float metal = 0.0;

	if (kind == 1) {
		// 쌓은 돌: 줄마다 엇갈린 돌덩이 + 움푹한 줄눈
		float bh = 0.42;
		float bw = 0.95;
		float row = floor(fc.y / bh);
		float ux = fc.x / bw + 0.5 * mod(row, 2.0) + hash1(row) * 0.3;
		if (rad_on) {
			float cnt = max(floor(6.2832 * radial / bw), 4.0);
			ux = ang / 6.2832 * cnt + 0.5 * mod(row, 2.0);
		}
		vec2 f = vec2(fract(ux), fract(fc.y / bh));
		float d = min(min(f.x, 1.0 - f.x) * bw, min(f.y, 1.0 - f.y) * bh);
		groove = 1.0 - smoothstep(0.012, 0.05, d);
		tint = hash2(vec2(floor(ux), row)) - 0.5;
		shade = 0.94 + 0.1 * smoothstep(0.0, 0.14, d);
	} else if (kind == 2) {
		// 나무: 결 방향(grain)으로 길게 흐르는 나뭇결 + 옹이. plank_w > 0 이면 결과 나란한 널 틈도 그림
		vec3 gax = normalize(grain);
		float pg = dot(lp, gax);
		vec3 sdir = cross(nl, gax);
		float sl = length(sdir);
		float pc = sl > 0.3 ? dot(lp, sdir / sl) : length(lp - gax * pg);
		float pid = 0.0;
		float pf = 0.5;
		if (plank_w > 0.001) {
			pid = floor(pc / plank_w);
			pf = fract(pc / plank_w);
			groove = 1.0 - smoothstep(0.02, 0.08, min(pf, 1.0 - pf));
		}
		float off = pid * 7.3 + oid * 31.0;
		float gr = noise2(vec2(pg * 1.1 + off, pc * 42.0 + off)) * 0.6 + noise2(vec2(pg * 3.5 + off, pc * 120.0)) * 0.4;
		float streaks = 0.5 + 0.5 * sin(pc * 95.0 + noise2(vec2(pg * 0.9 + off, pc * 6.0)) * 9.0);
		float knot = smoothstep(0.1, 0.0, length(vec2((fract(pg / 2.3 + hash1(pid + oid * 9.0)) - 0.5) * 2.3, pc - (hash1(pid + 4.0 + oid) - 0.5) * 0.12)));
		tint = (hash1(pid + oid * 17.0) - 0.5) * 0.9 + (gr - 0.5) * 0.7 + (streaks - 0.5) * 0.35 - knot * 0.6;
		if (sl <= 0.3) {
			// 마구리 (잘린 면): 나이테
			tint = sin(pc * 70.0) * 0.4 - 0.3;
		}
		det_k = 0.35;
		moss_k *= 0.7;
	} else if (kind == 3) {
		// 기와: 줄마다 엇갈려 겹친 기와장
		float th = 0.3;
		float tw = 0.3;
		float vv = fc.y / th;
		float row = floor(vv);
		float fy = fract(vv);
		float ux = fc.x / tw + 0.5 * mod(row, 2.0);
		if (rad_on) {
			float cnt = max(floor(6.2832 * radial / tw), 6.0);
			ux = ang / 6.2832 * cnt + 0.5 * mod(row, 2.0);
		}
		float fx = fract(ux);
		groove = max(1.0 - smoothstep(0.02, 0.09, min(fx, 1.0 - fx)), 1.0 - smoothstep(0.0, 0.14, min(fy, 1.0 - fy)));
		shade = mix(0.8, 1.08, sin(fx * 3.1416)) * mix(0.82, 1.06, fy);
		tint = (hash2(vec2(floor(ux), row)) - 0.5) * 1.3;
		det_k = 0.6;
	} else if (kind == 4) {
		// 홈 파인 기둥: 세로 홈 + 돌 토막 이음매
		float side = 1.0 - step(0.7, an.y);
		float fl = cos(ang * 20.0);
		groove = smoothstep(0.2, -0.95, fl) * 0.55 * side;
		bump += tu * sin(ang * 20.0) * 0.55 * side;
		float dj = fract(lp.y / 1.15 + 0.5);
		float joint = (1.0 - smoothstep(0.0, 0.02, min(dj, 1.0 - dj))) * side;
		groove = max(groove, joint);
		tint = (hash1(floor(lp.y / 1.15 + 0.5)) - 0.5) * 0.5;
	} else if (kind == 5) {
		// 뼈: 매끈하고 잔 구멍, 오목한 곳은 누렇게
		det_k = 0.35;
		float pore = smoothstep(0.62, 0.8, noise3(lp * 14.0));
		float age = fbm3(lp * 1.4);
		c = mix(c, c * vec3(0.9, 0.8, 0.58), smoothstep(0.4, 0.75, age) * 0.6);
		c *= 1.0 - pore * 0.22;
		float fib = noise3(lp * vec3(22.0, 2.0, 22.0));
		c *= 0.94 + 0.1 * fib;
		r = 0.5;
		moss_k *= 0.45;
	} else if (kind == 6) {
		// 벗겨진 칠: 칠이 떨어진 자리로 돌이 드러남 + 녹물 자국
		float chip = smoothstep(0.56, 0.62, fbm3(lp * 1.5) + (noise3(lp * 9.0) - 0.5) * 0.12);
		vec3 under = vec3(0.56, 0.54, 0.48);
		c = mix(c, under, chip);
		float rust = smoothstep(0.55, 0.85, noise2(vec2(ang * 5.0 + lp.x * 2.0, lp.y * 0.35)));
		c = mix(c, c * vec3(0.78, 0.6, 0.45), rust * 0.45 * (1.0 - chip));
		det_k = mix(0.4, 1.0, chip);
		r = mix(0.5, 0.9, chip);
		groove = chip * 0.3;
	} else if (kind == 7) {
		// 산호: 오돌토돌한 폴립 + 밝은 끝 · 가장자리
		det_k = 0.0;
		vec3 q = lp * 34.0;
		float polyp = smoothstep(0.6, 0.78, noise3(q * 0.9) * 0.7 + noise3(q * 2.1 + 5.0) * 0.3);
		float blot = fbm3(lp * 3.0);
		c *= 0.82 + 0.3 * blot;
		c = mix(c, min(c * 1.5 + 0.12, vec3(1.0)), polyp * 0.6);
		c = mix(c, min(c * 1.25 + 0.08, vec3(1.0)), smoothstep(0.2, 0.9, wn.y) * 0.4);
		bump = (vec3(noise3(q * 0.5), noise3(q * 0.5 + 3.0), noise3(q * 0.5 + 6.0)) - 0.5) * 0.9;
		r = 0.6;
		moss_k = 0.0;
	} else if (kind == 8) {
		// 토기: 물레 자국 + 칠한 띠 + 따개비
		det_k = 0.5;
		float ring = sin(lp.y * 70.0);
		c *= 0.95 + 0.05 * ring;
		bump.y += ring * 0.12;
		float band = smoothstep(0.035, 0.02, abs(lp.y - 0.62)) + smoothstep(0.02, 0.01, abs(lp.y - 0.5)) + smoothstep(0.02, 0.01, abs(lp.y - 0.74));
		c = mix(c, vec3(0.16, 0.1, 0.08), clamp(band, 0.0, 1.0) * 0.8);
		float zig = smoothstep(0.02, 0.0, abs(lp.y - 0.62 - (abs(fract(ang * 2.5) - 0.5) - 0.25) * 0.1));
		c = mix(c, vec3(0.9, 0.82, 0.66), zig * 0.8);
		vec3 q = lp * 16.0;
		float barn = smoothstep(0.3, 0.2, length(fract(q) - 0.5)) * step(0.8, hash3(floor(q)));
		c = mix(c, vec3(0.88, 0.86, 0.8), barn);
		bump += normalize(fract(q) - 0.5 + 1e-4) * barn * 0.6;
		r = 0.7;
		moss_k *= 0.5;
	} else if (kind == 9) {
		// 녹슨 쇠: 검은 쇠 위로 번진 붉은 녹 + 얽은 자국 + 따개비
		float rs = fbm3(lp * 2.2) + (noise3(lp * 13.0) - 0.5) * 0.25;
		float rk = smoothstep(0.32, 0.58, rs);
		c = mix(c, vec3(0.4, 0.19, 0.1) * (0.7 + 0.6 * noise3(lp * 20.0)), rk);
		c = mix(c, vec3(0.62, 0.34, 0.14), smoothstep(0.6, 0.8, rs) * 0.6);
		vec3 q = lp * 11.0;
		float barn = smoothstep(0.3, 0.2, length(fract(q) - 0.5)) * step(0.86, hash3(floor(q)));
		c = mix(c, vec3(0.8, 0.79, 0.72), barn);
		r = mix(0.5, 0.95, max(rk, barn));
		metal = (1.0 - rk) * (1.0 - barn) * 0.65;
		moss_k *= 0.5;
	}

	c *= mix(vec3(1.0), det / 0.9, det_k);
	c *= shade * (1.0 + tint * 0.24);
	c *= 1.0 - groove * 0.45;

	if (kind != 7) {
		// 물때: 세로면을 타고 흐른 얼룩, 오목한 곳의 때
		float streak = noise2(vec2(dot(wpos.xz, vec2(0.7, 0.71)) * 2.6, wpos.y * 0.22));
		c *= 1.0 - 0.2 * smoothstep(0.5, 0.9, streak) * (1.0 - abs(wn.y));
		c *= 0.9 + 0.2 * fbm3(wpos * 0.35);
		// 이끼 · 해조: 위를 보는 면과 틈에 잘 낌
		float mn = fbm3(wpos * 0.9);
		float m = smoothstep(0.2, 0.75, wn.y) * smoothstep(0.36, 0.6, mn)
			+ 0.6 * smoothstep(0.55, 0.75, fbm3(wpos * 0.55 + 7.0)) * (0.35 + groove);
		m = clamp(m * moss_k, 0.0, 0.92);
		vec3 moss_c = mix(vec3(0.16, 0.3, 0.17), vec3(0.34, 0.5, 0.24), noise3(wpos * 5.0));
		c = mix(c, moss_c, m);
		r = mix(r, 0.95, m);
		bump += (vec3(noise3(wpos * 11.0), 0.5, noise3(wpos * 11.0 + 4.0)) - 0.5) * m * 0.6;
	}

	ALBEDO = c;
	ROUGHNESS = clamp(r + groove * 0.1, 0.05, 1.0);
	SPECULAR = 0.4;
	METALLIC = metal;
	AO = 1.0 - groove * 0.5;
	AO_LIGHT_AFFECT = 0.5;
	vec3 n_local = normalize(nl + (bump - nl * dot(bump, nl)) * 0.7);
	NORMAL = normalize((VIEW_MATRIX * vec4(mat3(bx, by, bz) * n_local, 0.0)).xyz);
	if (kind == 7) {
		RIM = 0.5;
		RIM_TINT = 0.8;
	}
	float t = TIME * 0.5;
	float cs = caustic(wpos.xz * 0.35, t) + 0.6 * caustic(wpos.xz * 0.6 + 3.1, t * 1.3);
	EMISSION = vec3(0.35, 0.62, 0.52) * cs * 0.16 * clamp(wn.y, 0.0, 1.0) * caustics;
}
