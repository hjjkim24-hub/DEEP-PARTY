shader_type spatial;
// 다시마: 위로 갈수록 크게 흔들림. 뿌리는 진한 올리브, 끝은 금빛 초록 (UV.y: 0=뿌리 1=끝)
render_mode cull_disabled;
uniform vec3 base_color : source_color = vec3(0.16, 0.26, 0.08);
uniform vec3 tip_color : source_color = vec3(0.62, 0.68, 0.22);
uniform float phase = 0.0;
uniform float height = 6.0;
varying float hy;

void vertex() {
	hy = UV.y;
	float k = hy * hy * height * 0.09;
	VERTEX.x += sin(TIME * 1.0 + phase + hy * 3.0) * k;
	VERTEX.z += cos(TIME * 0.75 + phase * 1.3 + hy * 2.5) * k * 0.6;
}

void fragment() {
	vec3 c = mix(base_color, tip_color, smoothstep(0.0, 1.0, hy));
	// 잎 가운데 줄
	c *= 0.85 + 0.25 * (1.0 - abs(UV.x - 0.5) * 2.0);
	ALBEDO = c;
	ROUGHNESS = 0.5;
	EMISSION = tip_color * 0.06 * hy;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
