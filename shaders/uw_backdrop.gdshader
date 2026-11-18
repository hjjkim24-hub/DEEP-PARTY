shader_type spatial;
render_mode unshaded, fog_disabled, cull_front, shadows_disabled;
// 물속 먼 배경: 아래는 깊은 남청, 위(수면 쪽)로 갈수록 밝은 청록 + 수면 근처 빛 번짐
uniform vec3 deep : source_color = vec3(0.012, 0.09, 0.12);
uniform vec3 high : source_color = vec3(0.05, 0.3, 0.36);
uniform float y0 = -6.0;
uniform float y1 = 14.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = clamp((wpos.y - y0) / (y1 - y0), 0.0, 1.0);
	vec3 c = mix(deep, high, pow(t, 1.6));
	float w = sin(wpos.x * 0.15 + TIME * 0.2) * sin(wpos.z * 0.13 - TIME * 0.17);
	c += vec3(0.02, 0.06, 0.06) * w * t * t;
	ALBEDO = c;
}
