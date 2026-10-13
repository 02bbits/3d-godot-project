shader_type spatial;
render_mode blend_mix, unshaded;

#include "util/freshnel.gdshaderinc"
#include "util/blend.gdshaderinc"
#include "util/alpha.gdshaderinc"

group_uniforms fresnel;
uniform float fresnel_amount : hint_range(0.0, 5.0, 0.05) = 1.0;
uniform float fresnel_exponent = 1.0;
uniform sampler2D fresnel_gradient;

group_uniforms Mask;
uniform bool enable_mask = false;
uniform sampler2D mask_texture;
uniform vec2 mask_scroll = vec2(0.0);
uniform vec2 mask_scale = vec2(1.0);
uniform int mask_blend_mode : hint_range(0, 11, 1) = 0;
uniform float mask_blend : hint_range(0.0, 1.0, 0.1) = 0.0;

group_uniforms Emission;
uniform float emission_strength = 1.0;

group_uniforms color;
uniform vec4 primary_color : source_color;
uniform vec4 secondary_color : source_color;
uniform vec4 tertiary_color : source_color;

group_uniforms ProximityFade;
uniform bool proximity_fade = false;
uniform float proximity_fade_distance : hint_range(0.0, 4096.0, 0.01) = 1.0;

group_uniforms Transparency;
uniform float alpha_multiplier : hint_range(0.0, 1.0, 0.05) = 0.954;
uniform int alpha_mode : hint_range(0, 3, 1) = 0;
uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform float dither_cutoff : hint_range(0.0, 1.0, 0.01) = 0.8;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	float fres = fresnel(fresnel_amount, NORMAL, VIEW);
	float value = texture(fresnel_gradient, vec2(fres,0.0)).r;
	value = pow(value, fresnel_exponent);

	if(enable_mask){
		float mask_value = texture(mask_texture, (UV * mask_scale) + (vec2(TIME) * mask_scroll)).r;
		value = mix(value, blendf(value, mask_value, mask_blend_mode), mask_blend);
		value = clamp(value, 0.0, 1.0);
	}

	ALBEDO = mix(secondary_color, primary_color, value).rgb * emission_strength;

	float alpha = value * alpha_multiplier;

	// Proximity Fade: Enabled
	if(proximity_fade){
		float proximity_depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
		vec4 proximity_view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, proximity_depth_tex, 1.0);
		proximity_view_pos.xyz /= proximity_view_pos.w;
		alpha *= clamp(1.0 - smoothstep(proximity_view_pos.z + proximity_fade_distance, proximity_view_pos.z, VERTEX.z), 0.0, 1.0);
	}

	if(alpha_mode == 0){
		ALPHA = alpha;
	} else {
		if(alpha_discard(alpha, FRAGCOORD, alpha_mode, dither_cutoff, alpha_cutoff)){
			discard;
		}
	}
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
