shader_type canvas_item;
// 튜토리얼 스포트라이트: 화면을 어둡게 하고 네 점으로 된 칸 모양만 딱 맞게 뚫어요 + 반짝이는 테두리
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform vec2 q0;
uniform vec2 q1;
uniform vec2 q2;
uniform vec2 q3;
uniform vec4 dim_color : source_color = vec4(0.0, 0.05, 0.05, 0.62);
uniform vec4 ring_color : source_color = vec4(0.5, 0.94, 0.86, 1.0);
uniform float grow = 4.0;
uniform float ring_w = 4.0;

float sd(vec2 p, vec2 a, vec2 b) {
	vec2 e = b - a;
	vec2 n = normalize(vec2(-e.y, e.x));
	return dot(p - a, n);
}

void fragment() {
	vec2 p = UV * rect_size;
	float e0 = sd(p, q0, q1);
	float e1 = sd(p, q1, q2);
	float e2 = sd(p, q2, q3);
	float e3 = sd(p, q3, q0);
	// 감는 방향과 상관없이: 안쪽이면 d > 0
	float d = max(min(min(e0, e1), min(e2, e3)), min(min(-e0, -e1), min(-e2, -e3))) + grow;
	float outside = 1.0 - smoothstep(-0.8, 0.8, d);
	float ring = ring_color.a * (1.0 - smoothstep(ring_w * 0.5, ring_w * 0.5 + 1.4, abs(d + ring_w * 0.5)));
	COLOR = vec4(mix(dim_color.rgb, ring_color.rgb, clamp(ring * 2.0, 0.0, 1.0)), max(dim_color.a * outside, ring));
}
