shader_type spatial;
render_mode cull_disabled;

// 미니게임 바다 수면: 겹친 파도(게르스트너) + 프레넬 하늘 반사 + 물마루 거품
uniform vec3 deep : source_color = vec3(0.012, 0.05, 0.075);
uniform vec3 shallow : source_color = vec3(0.03, 0.16, 0.19);
uniform vec3 sky : source_color = vec3(0.36, 0.34, 0.42);
uniform vec3 foam_col : source_color = vec3(0.86, 0.92, 0.93);
uniform float amp = 0.35;
uniform float choppy = 0.35;
uniform float speed = 1.0;
uniform vec2 calm_center = vec2(0.0);   // 무대 근처는 잔잔하게
uniform float calm_radius = 0.0;

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

void fragment() {
	vec3 v = normalize(-VERTEX);
	float fr = pow(1.0 - clamp(dot(NORMAL, v), 0.0, 1.0), 4.0);
	float t = TIME * speed;
	// 잔물결
	vec2 q = wpos.xz;
	float e = 0.08;
	float h0 = noise(q * 1.7 + vec2(t * 0.6, t * 0.2)) + noise(q * 3.9 - vec2(t * 0.4, -t * 0.7)) * 0.5;
	float hx = noise((q + vec2(e, 0.0)) * 1.7 + vec2(t * 0.6, t * 0.2)) + noise((q + vec2(e, 0.0)) * 3.9 - vec2(t * 0.4, -t * 0.7)) * 0.5;
	float hz = noise((q + vec2(0.0, e)) * 1.7 + vec2(t * 0.6, t * 0.2)) + noise((q + vec2(0.0, e)) * 3.9 - vec2(t * 0.4, -t * 0.7)) * 0.5;
	vec3 rip = (VIEW_MATRIX * vec4(-(hx - h0) / e, 0.0, -(hz - h0) / e, 0.0)).xyz;
	NORMAL = normalize(NORMAL + rip * 0.06);
	vec3 col = mix(deep, shallow, clamp(crest * 0.5 + 0.35, 0.0, 1.0));
	col = mix(col, sky, clamp(fr * 0.85, 0.0, 0.85));
	// 거품: 물마루 꼭대기에만 가늘게 (잘게 부서진 무늬)
	float fn = noise(q * 6.0 + t * 0.8) * 0.6 + noise(q * 13.0 - t) * 0.4;
	float foam = smoothstep(0.86, 1.05, crest + (fn - 0.5) * 0.3) * smoothstep(0.55, 0.8, fn);
	col = mix(col, foam_col, foam * 0.45);
	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
