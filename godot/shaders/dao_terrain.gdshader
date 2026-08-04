shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D palette : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D palette_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D mask_a : filter_linear, repeat_disable;
uniform sampler2D mask_a2 : filter_linear, repeat_disable;
uniform vec4 pal_dim = vec4(0.5, 0.25, 2.0, 4.0);
uniform vec4 pal_param = vec4(0.0625, 0.03125, 0.375, 0.1875);
uniform vec4 uv_scales0 = vec4(24.0);
uniform vec4 uv_scales1 = vec4(24.0);

void fragment() {
    vec4 weights0 = texture(mask_a, UV);
    vec4 weights1 = texture(mask_a2, UV);
    float total_weight = dot(weights0, vec4(1.0)) + dot(weights1, vec4(1.0));
    vec3 color = vec3(0.0);
    vec3 tangent_normal = vec3(0.0);
    float specular_value = 0.0;
    for (int layer = 0; layer < 8; layer++) {
        float weight = layer < 4 ? weights0[layer] : weights1[layer - 4];
        if (weight <= 0.0001) continue;
        float scale = layer < 4 ? uv_scales0[layer] : uv_scales1[layer - 4];
        float col = floor(float(layer) / pal_dim.w);
        float row = mod(float(layer), pal_dim.w);
        vec2 origin = vec2(col * pal_dim.x + pal_param.x, row * pal_dim.y + pal_param.y);
        vec2 atlas_uv = origin + fract(UV * scale) * pal_param.zw;
        vec4 diffuse_sample = texture(palette, atlas_uv);
        vec3 normal_sample = texture(palette_normal, atlas_uv).rgb * 2.0 - 1.0;
        color += diffuse_sample.rgb * weight;
        tangent_normal += normal_sample * weight;
        specular_value += diffuse_sample.a * weight;
    }
    float divisor = max(total_weight, 0.0001);
    ALBEDO = color / divisor;
    NORMAL_MAP = normalize(tangent_normal / divisor) * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 1.0;
    METALLIC = 0.0;
    ROUGHNESS = mix(0.92, 0.38, clamp(specular_value / divisor, 0.0, 1.0));
}
