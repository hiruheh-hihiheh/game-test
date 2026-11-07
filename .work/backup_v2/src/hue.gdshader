shader_type canvas_item;

// Recolours a sprite without extra art, and can flash it white when hit.
uniform float hue = 0.0;
uniform float flash = 0.0;

vec3 rotate_hue(vec3 c, float amount) {
	const vec3 axis = vec3(0.57735);
	float a = amount * 6.2831853;
	float ca = cos(a);
	return c * ca + cross(axis, c) * sin(a) + axis * dot(axis, c) * (1.0 - ca);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.rgb = mix(rotate_hue(c.rgb, hue), vec3(1.0), flash);
	COLOR = c;
}
