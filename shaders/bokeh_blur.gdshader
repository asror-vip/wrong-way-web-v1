shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 15.0) = 0.0;
uniform vec4 tint_color : source_color = vec4(0.04, 0.05, 0.09, 0.0);
uniform float luminance_boost : hint_range(0.0, 1.0) = 0.16;
uniform float contrast : hint_range(0.5, 2.0) = 1.05;
uniform float fade_left : hint_range(0.0, 0.5) = 0.0;
uniform float fade_right : hint_range(0.0, 0.5) = 0.0;

void fragment() {
	vec4 col;
	if (blur_amount <= 0.01) {
		col = texture(TEXTURE, UV);
	} else {
		// Optimized 5-tap tent filter (mobile-friendly, zero fill-rate lag)
		vec2 ps = TEXTURE_PIXEL_SIZE * blur_amount;
		col = texture(TEXTURE, UV) * 0.40;
		col += texture(TEXTURE, UV + vec2(ps.x, ps.y)) * 0.15;
		col += texture(TEXTURE, UV + vec2(-ps.x, ps.y)) * 0.15;
		col += texture(TEXTURE, UV + vec2(ps.x, -ps.y)) * 0.15;
		col += texture(TEXTURE, UV + vec2(-ps.x, -ps.y)) * 0.15;
		
		col.rgb = mix(col.rgb, tint_color.rgb, tint_color.a);
		// Atmospheric background contrast: lift dark midtones for crisp silhouette readability
		col.rgb = (col.rgb - 0.5) * contrast + 0.5;
		col.rgb += vec3(luminance_boost);
		col.rgb = clamp(col.rgb, 0.0, 1.0);
	}
	
	// Smooth organic boundary edge fade for biome transitions
	float alpha_mult = 1.0;
	if (fade_left > 0.001) {
		alpha_mult *= smoothstep(0.0, fade_left, UV.x);
	}
	if (fade_right > 0.001) {
		alpha_mult *= (1.0 - smoothstep(1.0 - fade_right, 1.0, UV.x));
	}
	col.a *= alpha_mult;
	COLOR = col;
}
