shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 hair_tint : source_color = vec4(1.0);
uniform float roughness : hint_range(0.1, 0.9) = 0.68;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.34;

void fragment() {
	vec4 base = texture(albedo_texture, UV);
	ALBEDO = base.rgb * hair_tint.rgb;
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	NORMAL_MAP = texture(normal_texture, UV).xyz;
	NORMAL_MAP_DEPTH = 0.72;
	ROUGHNESS = roughness;
	SPECULAR = 0.12;
	ANISOTROPY = 0.32;
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
}
