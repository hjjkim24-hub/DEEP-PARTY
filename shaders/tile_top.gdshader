shader_type spatial;
// 칸 윗면: 물에 오래 잠긴 옛 신전의 돌판.
//   돌 위에 칠한 안료(칸 색)가 군데군데 벗겨져 돌이 드러나고, 가장자리일수록 많이 닳음
//   테두리는 청동 상감 (녹청이 슬어 푸르스름) · 그림은 돌에 새겨 판 홈에 조개껍데기 회반죽을 메움
//   홈 · 구석에는 모래와 펄이 끼고, 가장자리에는 이끼 얼룩과 작은 따개비
uniform vec4 tile_color : source_color = vec4(0.27, 0.59, 0.9, 1.0);
uniform vec4 ink_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform vec4 border_color : source_color = vec4(0.93, 0.94, 0.9, 1.0);
uniform sampler2D icon_tex : source_color, filter_linear_mipmap;
uniform sampler2D border_tex : source_color, filter_linear_mipmap;
uniform sampler2D det_tex : source_color, filter_linear_mipmap, repeat_enable;   // 돌 결
uniform sampler2D det_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float icon_scale = 0.62;
uniform float caustics = 1.0;   // 물속 빛 무늬 (하늘 위 배에서는 0)
uniform float weather = 1.0;    // 물때 · 이끼 · 따개비 정도 (배 위는 적게)
// 대각선으로 반씩 나뉜 칸 (크라켄의 보물상자: 왼쪽 위 = tile_color · icon_tex, 오른쪽 아래 = tile_color2 · icon_tex2)
uniform bool split = false;
uniform vec4 tile_color2 : source_color = vec4(0.1, 0.3, 0.22, 1.0);
uniform vec4 ink_color2 : source_color = vec4(0.7, 1.0, 0.6, 1.0);
uniform sampler2D icon_tex2 : source_color, filter_linear_mipmap;
varying vec3 wpos;
varying vec3 ax;    // 칸의 로컬 x · z 축 (월드)
varying vec3 az;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	return noise(p) * 0.5 + noise(p * 2.03 + 11.0) * 0.3 + noise(p * 4.1 + 23.0) * 0.2;
}
// 금: 보로노이 칸 경계까지 거리 (F2 - F1)
float crack_d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.0));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}
float caustic(vec2 p, float t) {
	float a = sin(p.x * 3.1 + sin(p.y * 2.3 + t) * 1.7 + t);
	float b = sin(p.y * 3.7 + sin(p.x * 1.9 - t * 1.3) * 1.5 - t * 0.8);
	return pow(max(a * b, 0.0), 2.5);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ax = MODEL_MATRIX[0].xyz;
	az = MODEL_MATRIX[2].xyz;
}

// 그림은 칸이 돌아가 있어도 늘 똑바로 (월드 기준으로 펴서 읽음) — 테두리는 칸을 따라감
vec2 icon_uv(vec2 uv) {
	vec2 d = uv - 0.5;
	vec3 w = ax * d.x + az * d.y;
	return vec2(w.x, w.z) / max(length(ax), 0.0001) / icon_scale + 0.5;
}
float split_side(vec2 uv) {
	return step(1.0, uv.x + uv.y);
}
float split_icon(sampler2D tex, vec2 uv, vec2 c, float lod) {
	vec2 iuv = (uv - c) / 0.36 + 0.5;
	if (iuv.x <= 0.0 || iuv.x >= 1.0 || iuv.y <= 0.0 || iuv.y >= 1.0) {
		return 0.0;
	}
	return textureLod(tex, iuv, lod).a;
}
float icon_a(vec2 uv, float lod) {
	if (split) {
		float sd = split_side(uv);
		return mix(split_icon(icon_tex, uv, vec2(0.33), lod), split_icon(icon_tex2, uv, vec2(0.67), lod), sd);
	}
	vec2 iuv = icon_uv(uv);
	if (iuv.x <= 0.0 || iuv.x >= 1.0 || iuv.y <= 0.0 || iuv.y >= 1.0) {
		return 0.0;
	}
	return textureLod(icon_tex, iuv, lod).a;
}
float seam_a(vec2 uv) {
	return split ? 1.0 - smoothstep(0.012, 0.026, abs(uv.x + uv.y - 1.0) * 0.7071) : 0.0;
}
// 높이: 청동 테두리는 살짝 도드라지고, 그림은 파인 홈 (회반죽은 홈보다 조금 낮게 메워짐)
float relief(vec2 uv) {
	float br = max(textureLod(border_tex, uv, 1.0).a, seam_a(uv));
	return br * 0.55 - icon_a(uv, 1.0) * 0.5;
}

void fragment() {
	vec2 uv = UV;
	vec2 wp = wpos.xz;
	float b = max(texture(border_tex, uv).a, seam_a(uv));
	float ic = icon_a(uv, 0.0);
	float sd = split ? split_side(uv) : 0.0;
	vec2 e2 = abs(uv - 0.5) * 2.0;
	float edge = max(e2.x, e2.y);                           // 0 가운데 → 1 가장자리
	// 돌: 실제 돌 사진 결 + 큰 얼룩
	vec3 det = texture(det_tex, wp * 0.42).rgb;
	float lum = dot(det, vec3(0.333));
	float blot = fbm(wp * 0.9);
	vec3 stone = vec3(0.52, 0.5, 0.46) * (0.5 + 0.85 * lum) * (0.82 + 0.3 * blot);
	// 안료: 돌결이 비쳐 보이고, 닳은 곳(가장자리 · 얼룩)은 벗겨져 돌이 드러남
	vec3 pig = mix(tile_color.rgb, tile_color2.rgb, sd);
	// 물에 오래 잠겨 바랜 안료: 채도가 빠지고 돌빛이 섞임 · 돌결이 비침
	pig = mix(pig, vec3(dot(pig, vec3(0.3, 0.55, 0.15))), 0.22);
	pig = mix(pig, stone, 0.18) * (0.62 + 0.6 * lum);
	pig = mix(pig, pig * vec3(0.9, 0.94, 0.88), blot * 0.6);
	float flake = fbm(wp * 2.6 + 5.0) * 0.7 + noise(wp * 11.0) * 0.3;
	float paint = smoothstep(0.26, 0.42, flake + 0.14 - smoothstep(0.5, 1.0, edge) * 0.55);
	vec3 c = mix(stone, pig, paint);
	// 새긴 그림: 조개 회반죽 (조금 누렇고 군데군데 빠져 홈 바닥이 보임)
	vec3 ink = mix(ink_color.rgb, ink_color2.rgb, sd);
	ink = mix(ink, vec3(0.9, 0.86, 0.76), 0.25) * (0.82 + 0.18 * noise(wp * 23.0));
	float chip = step(0.82, noise(wp * 14.0 + 3.0));
	vec3 groove = stone * 0.45;
	vec3 inlay = mix(ink, groove, chip * 0.8);
	// 홈 둘레에 낀 때 (그림 바깥쪽 흐릿한 띠)
	float halo = clamp(icon_a(uv, 3.5) * 1.6 - ic, 0.0, 1.0);
	c *= 1.0 - 0.35 * halo;
	c = mix(c, inlay, ic);
	// 청동 상감: 녹청이 고르지 않게 슬고, 닳은 모서리는 청동빛
	float pat = smoothstep(0.35, 0.7, fbm(wp * 5.0 + 9.0));
	vec3 bronze = mix(vec3(0.5, 0.36, 0.2), vec3(0.62, 0.48, 0.28), noise(wp * 30.0));
	vec3 verd = mix(vec3(0.26, 0.5, 0.42), vec3(0.42, 0.62, 0.52), noise(wp * 17.0));
	vec3 metal = mix(bronze, verd, pat * 0.85);
	c = mix(c, metal, b);
	// 모래 · 펄: 가장자리와 홈 둘레, 큰 얼룩 따라
	float grit = smoothstep(0.5, 0.82, fbm(wp * 3.1 + 40.0) * 0.65 + smoothstep(0.7, 1.0, edge) * 0.45 + halo * 0.35);
	grit *= 1.0 - 0.7 * ic;
	vec3 sand = vec3(0.66, 0.62, 0.5) * (0.85 + 0.3 * noise(wp * 40.0));
	c = mix(c, sand, grit * 0.6);
	// 이끼 얼룩 (가장자리 쪽 초록 기운)
	float moss = smoothstep(0.55, 0.85, fbm(wp * 1.7 + 70.0) + smoothstep(0.75, 1.0, edge) * 0.35) * weather;
	c = mix(c, c * vec3(0.62, 0.82, 0.6), moss * 0.55 * (1.0 - b));
	// 작은 따개비 (가장자리 근처에만, 하얀 점 + 가운데 구멍)
	vec2 cell = floor(wp * 9.0);
	vec2 f = fract(wp * 9.0) - 0.5;
	float has = step(0.86, hash(cell)) * smoothstep(0.8, 0.95, edge) * weather;
	float rr = length(f + (vec2(hash(cell + 3.0), hash(cell + 7.0)) - 0.5) * 0.4);
	float barn = has * (1.0 - smoothstep(0.17, 0.22, rr));
	float hole = has * (1.0 - smoothstep(0.05, 0.08, rr));
	c = mix(c, vec3(0.86, 0.84, 0.76), barn);
	c = mix(c, vec3(0.2, 0.18, 0.15), hole);
	// 가는 금 (일부 구역에만) + 가장자리로 갈수록 어두운 때
	float cd = crack_d(wp * 1.7 + 4.0);
	float crack = (1.0 - smoothstep(0.0, 0.022, cd)) * step(0.58, noise(wp * 0.8 + 2.0)) * (1.0 - b);
	c *= 1.0 - 0.45 * crack;
	c *= mix(1.0, 0.7, smoothstep(0.72, 1.0, edge));
	ALBEDO = c;
	// 노멀: 테두리 · 새김 + 돌 결 + 따개비 볼록
	float e = 0.006;
	float h0 = relief(uv);
	float hx = relief(uv + vec2(e, 0.0)) - h0;
	float hz = relief(uv + vec2(0.0, e)) - h0;
	vec3 dn = texture(det_nrm, wp * 0.42).rgb * 2.0 - 1.0;
	float bump = barn * 0.6 - hole * 0.6 - crack * 0.5;
	vec3 wn = normalize(vec3(0.0, 1.0, 0.0) - (normalize(ax) * hx + normalize(az) * hz) * 1.8
		+ vec3(dn.x, 0.0, dn.y) * (0.45 * (1.0 - b))
		+ vec3(f.x, 0.0, f.y) * bump * 0.8);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	METALLIC = b * (1.0 - pat * 0.85) * (1.0 - grit) * 0.75;
	float r_stone = mix(0.86, 0.72, paint);
	ROUGHNESS = mix(mix(r_stone, 0.6, ic), mix(0.42, 0.8, pat), b);
	ROUGHNESS = mix(ROUGHNESS, 0.95, grit * 0.7);
	SPECULAR = 0.45;
	float t = TIME * 0.5;
	EMISSION = vec3(0.35, 0.62, 0.52) * (caustic(wpos.xz * 0.35, t) + 0.6 * caustic(wpos.xz * 0.6 + 3.1, t * 1.3)) * 0.18 * caustics;
}
