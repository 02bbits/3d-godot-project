shader_type spatial;

// Opponent outline: an inverted hull drawn as the robot meshes'
// material_overlay (applied to remote copies only by player_outline.gd).
// The hull grows along smoothed normals that player_outline.gd bakes into
// TANGENT: the flat-shaded robot has one normal per face at every corner, so
// growing along NORMAL tears the faces apart. Skinning moves TANGENT like
// NORMAL, so the outline follows the animation. The width is in screen
// pixels, so it reads the same near and far.
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float width_px : hint_range(0.0, 12.0, 0.1) = 2.5;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 view_normal = mat3(MODELVIEW_MATRIX) * TANGENT;
	vec2 screen_dir = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (length(screen_dir) > 0.0001) {
		screen_dir = normalize(screen_dir);
	}
	clip.xy += screen_dir * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = color.rgb;
}
