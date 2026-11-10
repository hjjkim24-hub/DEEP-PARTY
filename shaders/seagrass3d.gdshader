shader_type spatial;
// 해초: 물결 따라 흔들림, 뿌리는 진하고 끝은 밝게 (UV.y: 0=뿌리 1=끝)
render_mode cull_disabled;
uniform vec3 base_color : source_color = vec3(0.1, 0.32, 0.17);
uniform vec3 tip_color : source_color = vec3(0.55, 0.78, 0.32);
uniform float sway = 0.22;
varying float vy;
varying float vary;

void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = UV.y;
	float w = sin(TIME * 1.3 + o.x * 0.35 + o.z * 0.27) * sway * h * h;
	VERTEX.x += w;
	VERTEX.z += w * 0.6;
	vy = h;
	vary = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	ALBEDO = mix(base_color, tip_color, vy) * (0.82 + 0.36 * vary);
	ROUGHNESS = 0.55;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
