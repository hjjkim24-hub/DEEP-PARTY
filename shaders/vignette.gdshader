shader_type canvas_item;
// 화면 가장자리와 아래쪽을 살짝 어둡게 (깊은 에메랄드 물 느낌)

uniform float strength = 0.6;
uniform vec4 tint : source_color = vec4(0.0, 0.07, 0.06, 1.0);

void fragment() {
	vec2 d = UV - vec2(0.5);
	d.x *= 1.25;
	float v = smoothstep(0.38, 0.9, length(d));
	v = max(v, smoothstep(0.65, 1.0, UV.y) * 0.55);
	COLOR = vec4(tint.rgb, v * strength);
}
