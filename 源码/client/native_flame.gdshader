shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float phase = 0.0;

void fragment() {
	vec2 uv = UV;
	// Keep the original head and palette. Only the trailing fire flows;
	// this changes presentation, never the published collision trajectory.
	float tail = pow(clamp(1.0 - uv.x, 0.0, 1.0), 1.4);
	uv.y += tail * (sin(uv.x * 18.0 - phase * 19.0) * 0.022
		+ sin(uv.x * 37.0 + phase * 27.0) * 0.010);
	float inside = step(0.0, uv.y) * step(uv.y, 1.0);
	COLOR = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0))) * COLOR * inside;
}
