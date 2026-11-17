shader_type spatial;
// 칸 윗면: 유약 바른 도자기 판. 놋쇠 테두리 상감 + 도드라진 무늬(양각) + 유약 얼룩 · 가장자리에 낀 모래 + 물빛
uniform vec4 tile_color : source_color = vec4(0.27, 0.59, 0.9, 1.0);
uniform vec4 ink_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform vec4 border_color : source_color = vec4(0.93, 0.94, 0.9, 1.0);
uniform sampler2D icon_tex : source_color, filter_linear_mipmap;
uniform sampler2D border_tex : source_color, filter_linear_mipmap;
uniform float icon_scale = 0.62;
uniform float caustics = 1.0;   // 물속 빛 무늬 (하늘 위 배에서는 0)
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
// 양각 높이: 테두리 + 무늬
float relief(vec2 uv) {
	float seam = split ? (1.0 - smoothstep(0.012, 0.026, abs(uv.x + uv.y - 1.0) * 0.7071)) * 0.7 : 0.0;
	return max(textureLod(border_tex, uv, 1.0).a * 0.7, seam) + icon_a(uv, 1.0);
}

void fragment() {
	vec2 uv = UV;
	float b = texture(border_tex, uv).a;
	float ic = icon_a(uv, 0.0);
	// 유약: 색이 고르지 않고(굽는 동안 흐른 자국), 도드라진 곳 둘레엔 유약이 고여 진함
	vec2 wp = wpos.xz;
	float flow = noise(wp * 1.3) * 0.6 + noise(wp * 4.0) * 0.4;
	float sd = split ? split_side(uv) : 0.0;
	vec3 glaze = mix(tile_color.rgb, tile_color2.rgb, sd) * (0.86 + 0.24 * flow);
	glaze += vec3(0.05) * (1.0 - length(uv - 0.5) * 1.6);
	float pool = max(textureLod(border_tex, uv, 4.0).a, icon_a(uv, 4.0));
	glaze *= 1.0 - 0.3 * pool * (1.0 - max(b, ic));
	// 잔 점 (유약 속 알갱이)
	glaze *= 1.0 - 0.12 * step(0.9, hash(floor(wp * 55.0)));
	// 놋쇠 테두리 (결 + 살짝 닳음)
	float wear = noise(wp * 6.0) * 0.5 + noise(wp * 17.0) * 0.5;
	vec3 brass = mix(vec3(0.78, 0.6, 0.26), vec3(0.95, 0.82, 0.5), wear);
	brass = mix(brass, border_color.rgb, 0.25);
	// 무늬: 도드라진 흰 유약
	vec3 ink = mix(ink_color.rgb, ink_color2.rgb, sd) * (0.92 + 0.08 * wear);
	if (split) {
		// 가운데 대각선 놋쇠 띠
		float seam = 1.0 - smoothstep(0.012, 0.026, abs(uv.x + uv.y - 1.0) * 0.7071);
		b = max(b, seam);
	}
	vec3 c = mix(glaze, brass, b);
	c = mix(c, ink, ic);
	// 가장자리 · 구석에 낀 모래와 물때
	vec2 e2 = abs(uv - 0.5) * 2.0;
	float rim = smoothstep(0.78, 1.0, max(e2.x, e2.y));
	float grit = smoothstep(0.42, 0.75, noise(wp * 3.1 + 40.0) * 0.6 + noise(wp * 9.0) * 0.4 + rim * 0.38) * (0.25 + 0.75 * rim);
	grit *= 1.0 - 0.6 * ic;
	c = mix(c, vec3(0.6, 0.57, 0.46) * (0.85 + 0.3 * noise(wp * 30.0)), grit * 0.55);
	ALBEDO = c;
	// 양각 노멀
	float e = 0.006;
	float h0 = relief(uv);
	float hx = relief(uv + vec2(e, 0.0)) - h0;
	float hz = relief(uv + vec2(0.0, e)) - h0;
	vec3 wn = normalize(vec3(0.0, 1.0, 0.0) - (normalize(ax) * hx + normalize(az) * hz) * 1.6
		+ vec3(noise(wp * 9.0) - 0.5, 0.0, noise(wp * 9.0 + 7.0) - 0.5) * 0.05);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	METALLIC = b * (1.0 - ic) * (1.0 - grit) * 0.85;
	ROUGHNESS = mix(mix(0.12 + 0.1 * flow, 0.34, max(b, ic)), 0.9, grit * 0.8);
	SPECULAR = 0.7;
	float t = TIME * 0.5;
	EMISSION = vec3(0.35, 0.62, 0.52) * (caustic(wpos.xz * 0.35, t) + 0.6 * caustic(wpos.xz * 0.6 + 3.1, t * 1.3)) * 0.18 * caustics;
}
