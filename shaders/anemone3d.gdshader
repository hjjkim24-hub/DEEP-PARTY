shader_type spatial;
// 말미잘: 촉수 끝이 살랑살랑 (UV.y: 0=뿌리 1=끝). 몸통엔 세로 줄무늬, 촉수 끝은 반투명하게 빛남
uniform vec3 base_color : source_color = vec3(0.9, 0.35, 0.5);
uniform vec3 tip_color : source_color = vec3(1.0, 0.85, 0.92);
uniform float phase = 0.0;
varying float vy;
varying vec3 lp;

void vertex() {
	vy = UV.y;
	lp = VERTEX;
	float k = vy * vy * 0.12;
	VERTEX.x += sin(TIME * 1.8 + phase + VERTEX.z * 4.0) * k;
	VERTEX.z += cos(TIME * 1.5 + phase + VERTEX.x * 4.0) * k;
}

void fragment() {
	float body = step(lp.y, 0.385) * step(vy, 0.001);
	float ang = atan(lp.x, lp.z);
	float stripe = 0.5 + 0.5 * sin(ang * 18.0);
	vec3 bc = base_color * mix(0.62, 0.95, stripe) * (0.75 + 0.6 * smoothstep(0.0, 0.4, lp.y));
	vec3 tc = mix(base_color, tip_color, smoothstep(0.25, 1.0, vy));
	ALBEDO = mix(tc, bc, body);
	ROUGHNESS = mix(0.35, 0.6, body);
	RIM = 0.6;
	RIM_TINT = 0.7;
	EMISSION = tip_color * 0.22 * smoothstep(0.6, 1.0, vy);
}
