shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_schlick_ggx;

// 미니게임 바다 수면 (자연스러운 바다)
//  · 파도: 바람 방향을 중심으로 퍼진 8겹 게르스트너 파 (긴 너울 ~ 짧은 물결)
//  · 잔물결: 실제 바다 물결 스펙트럼으로 구운 노멀맵 두 장이 서로 다른 방향 · 속도로 흐름
//  · 색: 물은 어두운 남청색, 밝은 건 하늘 반사(엔진 반사 · 프레넬)와 햇빛 반짝임에 맡김
//        파도 마루는 빛이 비쳐 살짝 청록 (물 속으로 스미는 빛)
//  · 거품: 높은 마루에만 레이스 무늬로, 물체가 물에 닿은 자리엔 깊이로 찾아 둘레 거품
uniform vec3 deep : source_color = vec3(0.0, 0.055, 0.09);
uniform vec3 shallow : source_color = vec3(0.02, 0.24, 0.26);
uniform vec3 sss_col : source_color = vec3(0.05, 0.42, 0.38);
uniform vec3 foam_col : source_color = vec3(0.92, 0.95, 0.96);
uniform float amp = 0.35;              // 파도 크기 (1 = 보통)
uniform float choppy = 0.55;           // 마루가 뾰족한 정도
uniform float speed = 1.0;
uniform vec2 wind = vec2(1.0, 0.3);
uniform vec2 calm_center = vec2(0.0);  // 무대 근처는 잔잔하게
uniform float calm_radius = 0.0;
uniform float edge_foam = 1.0;
uniform float crest_foam = 1.0;
uniform float detail = 1.0;            // 잔물결 노멀 세기
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 wpos;
varying vec3 wnrm;
varying float crest;

void wave(vec2 p, vec2 d, float wl, float a, float q, float t, inout vec3 off, inout vec3 tan, inout vec3 bin) {
	float k = 6.2831853 / wl;
	float c = sqrt(9.8 / k);
	float f = k * (dot(d, p) - c * t);
	float s = sin(f);
	float co = cos(f);
	float wa = k * a;
	off += vec3(d.x * q * a * co, a * s, d.y * q * a * co);
	tan += vec3(-d.x * d.x * q * wa * s, d.x * wa * co, -d.x * d.y * q * wa * s);
	bin += vec3(-d.x * d.y * q * wa * s, d.y * wa * co, -d.y * d.y * q * wa * s);
}

vec2 rot(vec2 v, float a) {
	return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * speed;
	float calm = calm_radius > 0.0 ? smoothstep(calm_radius, calm_radius * 2.2, length(w.xz - calm_center)) * 0.75 + 0.25 : 1.0;
	float A = amp * calm;
	vec2 wd = normalize(wind);
	vec3 off = vec3(0.0);
	vec3 tan = vec3(1.0, 0.0, 0.0);
	vec3 bin = vec3(0.0, 0.0, 1.0);
	// 파장 · 방향(바람에서 벌어진 각) · 높이 비율
	const int NW = 8;
	float wls[8] = float[](23.0, 15.5, 10.7, 7.4, 5.2, 3.7, 2.6, 1.8);
	float angs[8] = float[](0.0, 0.55, -0.45, 0.95, -0.85, 0.3, -1.25, 1.5);
	float hs[8] = float[](1.0, 0.62, 0.42, 0.28, 0.19, 0.12, 0.075, 0.05);
	for (int i = 0; i < NW; i++) {
		float a = A * hs[i];
		float k = 6.2831853 / wls[i];
		float q = choppy / (k * a * float(NW) + 0.0001);
		q = min(q, 1.0 / (k * a * float(NW) + 0.0001));
		wave(w.xz, rot(wd, angs[i]), wls[i], a, q, t, off, tan, bin);
	}
	VERTEX += off;
	wnrm = normalize(cross(bin, tan));
	NORMAL = wnrm;
	wpos = w + off;
	crest = off.y / max(A * 1.6, 0.001);
}

vec3 unpack(vec3 c) {
	return c * 2.0 - 1.0;
}

void fragment() {
	float t = TIME * speed;
	vec2 q = wpos.xz;
	float dist = length(VERTEX);
	// 잔물결 노멀 두 장 (+ 같은 B 를 크게 한 번 더): 바람 방향으로 흐름
	vec2 wd = normalize(wind);
	vec3 na = unpack(texture(normal_a, q / 26.0 + wd * t * 0.018).rgb);
	vec3 nb = unpack(texture(normal_b, rot(q, 0.7) / 9.5 - wd.yx * t * 0.03).rgb);
	vec3 nc = unpack(texture(normal_b, rot(q, -1.1) / 61.0 + wd * t * 0.006).rgb);
	float fade = mix(1.0, 0.35, smoothstep(25.0, 140.0, dist));
	vec2 slope = (na.xy * 0.55 + nb.xy * 0.35 * fade + nc.xy * 0.45) * detail;
	vec3 nw = normalize(wnrm + vec3(slope.x, 0.0, slope.y) * 0.55);
	vec3 n = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vec3 v = normalize(-VERTEX);
	// 물빛: 어두운 남청 + 마루로 스미는 빛
	float c01 = clamp(crest * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = deep + sss_col * pow(c01, 3.0) * 0.55 * (0.4 + 0.6 * (1.0 - clamp(dot(n, v), 0.0, 1.0)));
	// 물체 둘레: 얕아지는 물빛 + 거품
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 sp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float thick = (-sp.z / sp.w) - (-VERTEX.z);
	float near_obj = step(0.0, thick) * (1.0 - smoothstep(0.0, 2.2, thick));
	col = mix(col, shallow, near_obj * 0.55);
	float ft = texture(foam_tex, q / 7.0 + vec2(t * 0.01, 0.0)).r;
	float ft2 = texture(foam_tex, rot(q, 0.9) / 3.1 - vec2(0.0, t * 0.02)).r;
	float fpat = clamp(ft * 0.75 + ft2 * 0.5, 0.0, 1.0);
	float contact = step(0.0, thick) * (1.0 - smoothstep(0.0, 0.35 + fpat * 0.9, thick)) * edge_foam;
	contact = clamp(contact * (0.45 + fpat * 1.2), 0.0, 1.0);
	// 마루 거품: 가장 높은 꼭대기에서만, 무늬도 드문드문 (작은 흰 물결 부서짐)
	float cf = smoothstep(0.78, 1.0, c01) * crest_foam;
	float crest_f = clamp(cf * (fpat * 1.6 - 0.45), 0.0, 1.0) * fade;
	float foam = clamp(contact + crest_f * 0.85, 0.0, 1.0);
	ALBEDO = mix(col, foam_col, foam);
	NORMAL = normalize(mix(n, NORMAL, foam * 0.6));
	ROUGHNESS = mix(mix(0.035, 0.12, smoothstep(30.0, 200.0, dist)), 0.85, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
	ALPHA = 0.999;   // 투명 순서로 그려야 깊이 텍스처(물에 닿은 물체)를 읽을 수 있음
}
