shader_type canvas_item;
// 카드 둘레에서 일렁이는 오라: 둥근 사각형 바깥으로 불꽃처럼 너울대며 위로 피어오름
uniform vec4 aura_color : source_color = vec4(0.4, 1.0, 0.3, 1.0);
uniform vec2 rect_px = vec2(580.0, 760.0);   // 이 ColorRect 크기
uniform vec2 card_px = vec2(400.0, 580.0);   // 카드 크기 (가운데)
uniform float radius = 24.0;
uniform float strength = 1.0;
uniform float bright = 1.0;                  // 어두운 색(검붉은)은 진하게 덮도록

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return n2(p) * 0.55 + n2(p * 2.1 + 3.0) * 0.3 + n2(p * 4.3 + 7.0) * 0.15; }

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_px;
	float d = sd_box(p, card_px * 0.5, radius);
	float ang = atan(p.y, p.x);
	// 위로 피어오르는 불꽃 결 (둘레 각도 · 바깥 거리 · 시간)
	float flame = fbm(vec2(ang * 3.0 + sin(TIME * 0.7) * 0.3, d * 0.05 + TIME * 1.8 + p.y * 0.008));
	float tongues = pow(fbm(vec2(ang * 7.0, TIME * 1.1 - d * 0.02)), 2.0);
	float flick = 0.8 + 0.2 * sin(TIME * 6.0 + ang * 4.0);
	float reach = 10.0 + 55.0 * flame * flame * flick + 35.0 * tongues + max(-p.y, 0.0) * 0.05;
	float a = exp(-max(d, 0.0) / reach) * smoothstep(-6.0, 3.0, d);
	a *= 0.45 + 0.8 * flame;
	// 테두리에 딱 붙은 밝은 띠
	a += exp(-abs(d) / 3.5) * 0.7;
	// 사각형 가장자리 전에 완전히 사라지게
	float edge = min(rect_px.x - card_px.x, rect_px.y - card_px.y) * 0.5;
	a *= 1.0 - smoothstep(edge * 0.45, edge * 0.95, d);
	COLOR = vec4(aura_color.rgb * mix(1.0, 1.6, flame * bright), clamp(a * strength, 0.0, 1.0));
}
