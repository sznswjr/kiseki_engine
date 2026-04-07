#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
    float4 color    [[attribute(3)]];
};

struct VertexOut {
    float4 clipPosition [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 texCoord;
    float4 color;
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4   normalMatrixCol0;
    float4   normalMatrixCol1;
    float4   normalMatrixCol2;
};

struct Light {
    float4 direction;       // xyz = direction
    float4 colorAndAmbient; // xyz = color, w = ambientIntensity
};

struct MaterialUniforms {
    float4 ambient;         // xyz
    float4 diffuse;         // xyz
    float4 specular;        // xyz = specular, w = shininess
    int    hasTexture;
    int    _pad[3];
};

struct FragmentUniforms {
    Light            light;
    MaterialUniforms material;
    float4           cameraPosition; // xyz
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.clipPosition  = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldPosition = worldPos.xyz;

    // Reconstruct normal matrix from packed columns
    float3x3 normalMatrix = float3x3(uniforms.normalMatrixCol0.xyz,
                                      uniforms.normalMatrixCol1.xyz,
                                      uniforms.normalMatrixCol2.xyz);
    out.worldNormal = normalMatrix * in.normal;
    out.texCoord    = in.texCoord;
    out.color       = in.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant FragmentUniforms& fragUniforms [[buffer(0)]],
                              texture2d<float> diffuseTexture [[texture(0)]],
                              sampler texSampler [[sampler(0)]]) {
    Light light = fragUniforms.light;
    MaterialUniforms mat = fragUniforms.material;

    float3 N = normalize(in.worldNormal);
    float3 L = normalize(light.direction.xyz);
    float3 V = normalize(fragUniforms.cameraPosition.xyz - in.worldPosition);
    float3 H = normalize(L + V);

    // Ambient
    float ambientIntensity = light.colorAndAmbient.w;
    float3 ambient = mat.ambient.xyz * ambientIntensity;

    // Diffuse
    float NdotL = max(dot(N, L), 0.0);
    float3 diffuse = mat.diffuse.xyz * light.colorAndAmbient.xyz * NdotL;

    // Specular (Blinn-Phong)
    float shininess = mat.specular.w;
    float NdotH = max(dot(N, H), 0.0);
    float3 specular = mat.specular.xyz * light.colorAndAmbient.xyz * pow(NdotH, shininess);

    // Base color
    float3 baseColor;
    if (mat.hasTexture) {
        baseColor = diffuseTexture.sample(texSampler, in.texCoord).rgb;
    } else {
        baseColor = in.color.rgb;
    }

    float3 litColor = (ambient + diffuse) * baseColor + specular;
    return float4(litColor, in.color.a);
}
