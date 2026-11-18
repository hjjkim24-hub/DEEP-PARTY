shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_schlick_ggx;

// 미니게임 바다 수면
//  · 겹친 파도(게르스트너)로 출렁임 + 잔물결 노멀
//  · 깊을수록 진한 남색, 파도 마루는 빛이 비쳐 청록 (물 속으로 빛이 스며드는 느낌)
//  · 물체(뗏목 · 촉수 · 배)가 물에 닿은 자리는 깊이로 찾아 하얀 거품 띠
//  · 파도 마루의 거품 줄무늬
uniform vec3 deep : source_color = vec3(0.012, 0.05, 0.075);
uniform vec3 shallow : source_color = vec3(0.03, 0.16, 0.19);
uniform vec3 sky : source_color = vec3(0.36, 0.34, 0.42);
uniform vec3 sss_col : source_color = vec3(0.1, 0.55, 0.5);
uniform vec3 foam_col : source_color = vec3(0.9, 0.95, 0.96);
uniform float amp = 0.35;
uniform float choppy = 0.35;
uniform float speed = 1.0;
uniform vec2 calm_center = vec2(0.0);   // 무대 근처는 잔잔하게
uniform float calm_radius = 0.0;
uniform float edge_foam = 1.0;          // 물체 둘레 거품 세기
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 wpos;
varying float crest;

vec3 gerstner(vec2 p, vec2 dir, float wl, float a, float t, inout vec3 tan, inout vec3 bin) {
	float k = 6.2831 / wl;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float q = choppy / (k * a * 4.0 + 0.001);
	tan += vec3(-d.x * d.x * q * a * k * sin(f), d.x * a * k * cos(f), -d.x * d.y * q * a * k * sin(f));
	bin += vec3(-d.x * d.y * q * a * k * sin(f), d.y * a * k * cos(f), -d.y * d.y * q * a * k * sin(f));
	return vec3(d.x * q * a * cos(f), a * sin(f), d.y * q * a * cos(f));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * speed;
	float calm = calm_radius > 0.0 ? smoothstep(calm_radius, calm_radius * 2.2, length(w.xz - calm_center)) * 0.8 + 0.2 : 1.0;
	float a = amp * calm;
	vec3 tan = vec3(1.0, 0.0, 0.0);
	vec3 bin = vec3(0.0, 0.0, 1.0);
	vec3 off = vec3(0.0);
	off += gerstner(w.xz, vec2(1.0, 0.3), 14.0, a, t, tan, bin);
	off += gerstner(w.xz, vec2(-0.4, 1.0), 8.0, a * 0.55, t, tan, bin);
	off += gerstner(w.xz, vec2(0.7, -0.8), 4.5, a * 0.3, t, tan, bin);
	off += gerstner(w.xz, vec2(-1.0, -0.2), 2.3, a * 0.14, t, tan, bin);
	VERTEX += off;
	NORMAL = normalize(cross(bin, tan));
	wpos = w + off;
	crest = off.y / max(a, 0.001);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float ripples(vec2 q, float t) {
	return noise(q * 1.7 + vec2(t * 0.6, t * 0.2)) + noise(q * 3.9 - vec2(t * 0.4, -t * 0.7)) * 0.5 + noise(q * 9.0 + vec2(t, t * 0.3)) * 0.2;
}

void fragment() {
	float t = TIME * speed;
	vec2 q = wpos.xz;
	// 잔물결 (높이장 기울기 → 노멀)
	float e = 0.06;
	float h0 = ripples(q, t);
	float hx = ripples(q + vec2(e, 0.0), t);
	float hz = ripples(q + vec2(0.0, e), t);
	vec3 rip = (VIEW_MATRIX * vec4(-(hx - h0) / e, 0.0, -(hz - h0) / e, 0.0)).xyz;
	vec3 n = normalize(NORMAL + rip * 0.07);
	vec3 v = normalize(-VERTEX);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fr = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	// 물빛: 정면은 깊은 색, 파도 마루는 빛이 비쳐 청록
	vec3 col = mix(deep, shallow, clamp(crest * 0.45 + 0.4, 0.0, 1.0));
	col += sss_col * pow(clamp(crest * 0.5 + 0.35, 0.0, 1.0), 3.0) * 0.35;
	col = mix(col, sky, clamp(fr, 0.0, 0.75));
	// 물체 둘레 거품 (깊이 차이)
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 sp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -sp.z / sp.w;
	float water_z = -VERTEX.z;
	float thick = scene_z - water_z;
	float fn = noise(q * 5.0 + t * 0.9) * 0.6 + noise(q * 13.0 - t * 1.3) * 0.4;
	float shore = (1.0 - smoothstep(0.0, 0.55 + fn * 0.5, thick)) * step(0.0, thick) * edge_foam;
	shore *= smoothstep(0.25, 0.6, fn + 0.15);
	// 파도 마루 거품 (가늘게 부서진 줄)
	float cf = smoothstep(0.82, 1.05, crest + (fn - 0.5) * 0.35) * smoothstep(0.5, 0.78, fn);
	float foam = clamp(shore + cf * 0.5, 0.0, 1.0);
	col = mix(col, foam_col, foam);
	ALBEDO = col;
	NORMAL = n;
	ROUGHNESS = mix(0.04, 0.7, foam);
	SPECULAR = 0.7;
	METALLIC = 0.0;
	ALPHA = 0.999;   // 투명 순서로 그려야 깊이 텍스처(물 아래 · 물에 닿은 물체)를 읽을 수 있음
}
