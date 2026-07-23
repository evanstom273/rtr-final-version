shader_type canvas_item;
render_mode unshaded;

uniform vec4 background_top : source_color = vec4(0.047, 0.047, 0.052, 1.0);
uniform vec4 background_bottom : source_color = vec4(0.024, 0.024, 0.027, 1.0);
uniform vec4 centre_light : source_color = vec4(0.08, 0.075, 0.105, 1.0);

float hash(vec2 point) {
	return fract(sin(dot(point, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec3 base = mix(background_top.rgb, background_bottom.rgb, uv.y);
	float centre = max(0.0, 1.0 - length((uv - vec2(0.5)) * vec2(1.25, 1.0)));
	base += centre_light.rgb * centre * 0.08;
	float vignette = smoothstep(0.95, 0.28, length((uv - vec2(0.5)) * vec2(1.0, 0.82)));
	base *= mix(0.82, 1.0, vignette);
	float diagonal = sin((uv.x + uv.y) * 115.0) * 0.0025;
	float grain = (hash(floor(uv * vec2(960.0, 540.0))) - 0.5) * 0.011;
	COLOR = vec4(base + diagonal + grain, 1.0);
}
