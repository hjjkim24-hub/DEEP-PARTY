shader_type spatial;
// 다시마: 위로 갈수록 크게 흔들림
render_mode cull_disabled;
uniform vec4 color : source_color = vec4(0.16, 0.5, 0.28, 1.0);
uniform float phase = 0.0;
varying float hy;

void vertex() {
	hy = VERTEX.y;
	float k = VERTEX.y * VERTEX.y * 0.02;
	VERTEX.x += sin(TIME * 1.1 + phase + VERTEX.y * 0.35) * k;
	VERTEX.z += cos(TIME * 0.8 + phase * 1.3 + VERTEX.y * 0.3) * k * 0.6;
}

void fragment() {
	ALBEDO = color.rgb * (0.65 + 0.06 * hy);
	ROUGHNESS = 0.6;
}
