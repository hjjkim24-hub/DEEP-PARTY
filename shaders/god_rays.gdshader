shader_type canvas_item;
render_mode blend_add;
// 수면에서 비스듬히 내려오는 빛줄기 (모든 물체 위에 더해짐)

uniform float intensity = 0.20;
uniform vec2 source = vec2(0.32, -0.35);
uniform vec2 aspect = vec2(1.7778, 1.0);
uniform vec4 ray_color : source_color = vec4(0.80, 1.0, 0.92, 1.0);

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void fragment() {
	vec2 d = (UV - source) * vec2(aspect.x / aspect.y, 1.0);
	float ang = atan(d.x, d.y);
	float dist = length(d);

	float r = noise1(ang * 16.0 + TIME * 0.12) * 0.6 + noise1(ang * 34.0 - TIME * 0.2) * 0.4;
	r = smoothstep(0.42, 1.0, r);

	float fall = exp(-dist * 1.1);
	float vfade = 1.0 - smoothstep(0.15, 1.0, UV.y);
	float a = r * fall * vfade * intensity;

	COLOR = vec4(ray_color.rgb, a);
}
