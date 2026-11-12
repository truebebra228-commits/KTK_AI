shader_type canvas_item;
render_mode unshaded;

// Coordinates are pixels in the ORIGINAL 1254 x 1254 PNG, not Atlas UVs.
uniform vec2 feature_offset_pixels = vec2(0.0);
varying vec4 vertex_modulate;

void vertex() {
	// Fragment COLOR already contains a texture sample in canvas_item shaders.
	// Carry the untextured vertex modulation explicitly to avoid squaring it.
	vertex_modulate = COLOR;
}

float distance_to_segment(vec2 p, vec2 a, vec2 b) {
	vec2 axis = b - a;
	float along = clamp(dot(p - a, axis) / dot(axis, axis), 0.0, 1.0);
	return length(p - a - axis * along);
}

bool feature_mask(vec2 p, vec4 source, vec4 opaque_neighbors) {
	if (source.a <= 0.5 || max(source.r, max(source.g, source.b)) >= 0.16) {
		return false;
	}
	bool eyes = p.x >= 338.0 && p.x <= 912.0 && p.y >= 220.0 && p.y <= 445.0;
	if (eyes) {
		// Erode the opaque silhouette so the outer head rim stays stationary.
		eyes = all(greaterThan(opaque_neighbors, vec4(0.5)));
	}
	bool brows = p.y >= 35.0 && p.y <= 270.0
		&& (distance_to_segment(p, vec2(415.0, 65.0), vec2(628.0, 260.0)) <= 34.0
			|| distance_to_segment(p, vec2(838.0, 65.0), vec2(628.0, 260.0)) <= 34.0);
	return eyes || brows;
}

void fragment() {
	vec2 p = UV / TEXTURE_PIXEL_SIZE;
	vec4 original = texture(TEXTURE, UV);
	vec4 result = original;
	// The jaw and teeth remain the original drawing. At rest this is an exact
	// passthrough, with no white pupils or additional facial marks.
	if (p.y < 455.0 && max(abs(feature_offset_pixels.x), abs(feature_offset_pixels.y)) > 0.001) {
		vec4 opaque_neighbors = vec4(
			texture(TEXTURE, (p + vec2(35.0, 0.0)) * TEXTURE_PIXEL_SIZE).a,
			texture(TEXTURE, (p - vec2(35.0, 0.0)) * TEXTURE_PIXEL_SIZE).a,
			texture(TEXTURE, (p + vec2(0.0, 35.0)) * TEXTURE_PIXEL_SIZE).a,
			texture(TEXTURE, (p - vec2(0.0, 35.0)) * TEXTURE_PIXEL_SIZE).a);
		if (feature_mask(p, original, opaque_neighbors)) {
			vec2 head = (p - vec2(625.0, 300.0)) / vec2(265.0, 210.0);
			result = dot(head, head) <= 1.0
				? texture(TEXTURE, vec2(628.0, 335.0) * TEXTURE_PIXEL_SIZE)
				: vec4(0.0);
		}
		vec2 from = p - feature_offset_pixels;
		vec4 shifted = texture(TEXTURE, from * TEXTURE_PIXEL_SIZE);
		vec4 shifted_neighbors = vec4(
			texture(TEXTURE, (from + vec2(35.0, 0.0)) * TEXTURE_PIXEL_SIZE).a,
			texture(TEXTURE, (from - vec2(35.0, 0.0)) * TEXTURE_PIXEL_SIZE).a,
			texture(TEXTURE, (from + vec2(0.0, 35.0)) * TEXTURE_PIXEL_SIZE).a,
			texture(TEXTURE, (from - vec2(0.0, 35.0)) * TEXTURE_PIXEL_SIZE).a);
		if (feature_mask(from, shifted, shifted_neighbors)) {
			result = shifted;
		}
	}
	COLOR = result * vertex_modulate;
}
