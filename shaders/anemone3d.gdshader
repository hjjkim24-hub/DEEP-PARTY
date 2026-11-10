shader_type spatial;
// 말미잘: 촉수 끝이 살랑살랑 (UV.y: 0=뿌리 1=끝)
uniform vec3 base_color : source_color = vec3(0.9, 0.35, 0.5);
uniform vec3 tip_color : source_color = vec3(1.0, 0.85, 0.92);
uniform float phase = 0.0;
varying float vy;

void vertex() {
	vy = UV.y;
	float k = vy * vy * 0.12;
	VERTEX.x += sin(TIME * 1.8 + phase + VERTEX.z * 4.0) * k;
	VERTEX.z += cos(TIME * 1.5 + phase + VERTEX.x * 4.0) * k;
}

void fragment() {
	ALBEDO = mix(base_color, tip_color, smoothstep(0.4, 1.0, vy));
	ROUGHNESS = 0.4;
	EMISSION = tip_color * 0.12 * smoothstep(0.7, 1.0, vy);
}
