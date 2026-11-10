shader_type spatial;
// 위에서 비스듬히 내려오는 빛줄기 (더해지는 빛)
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 0.12;
uniform float phase = 0.0;

void fragment() {
	float edge = sin(UV.x * 3.14159);
	float fade = smoothstep(1.0, 0.25, UV.y) * smoothstep(0.0, 0.25, UV.y);
	float flick = 0.75 + 0.25 * sin(TIME * 0.6 + phase);
	ALBEDO = vec3(0.6, 0.95, 0.85) * edge * edge * fade * strength * flick;
}
