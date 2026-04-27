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
    float4 positionAndRange; // xyz = world position, w = range
    float4 colorAndAmbient;  // xyz = color * intensity, w = ambientIntensity
};

struct MaterialUniforms {
    float4 ambient;         // xyz
    float4 diffuse;         // xyz
    float4 specular;        // xyz = specular, w = shininess
    int    hasTexture;
    int    receivesShadow;
    int    _pad[2];
};

struct FragmentUniforms {
    Light            light;
    MaterialUniforms material;
    float4           cameraPosition; // xyz
};

struct ShadowUniforms {
    float4 lightPositionAndRange;
    int    shadowType;
    int    shadowEnabled;
    int    _pad[2];
};

// ---------------------------------------------------------------------------
// Shadow pass: depth-only vertex shader (no fragment shader needed)
// ---------------------------------------------------------------------------
struct ShadowVertexOut {
    float4 position [[position]];
    float3 worldPosition;
};

vertex ShadowVertexOut shadow_vertex(VertexIn in [[stage_in]],
                                      constant Uniforms& uniforms [[buffer(1)]]) {
    ShadowVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldPosition = worldPos.xyz;
    return out;
}

fragment float4 point_shadow_fragment(ShadowVertexOut in [[stage_in]],
                                      constant ShadowUniforms& shadowUniforms [[buffer(0)]]) {
    float distanceToLight = length(in.worldPosition - shadowUniforms.lightPositionAndRange.xyz);
    float normalizedDepth = clamp(distanceToLight / shadowUniforms.lightPositionAndRange.w, 0.0, 1.0);
    return float4(normalizedDepth, 0.0, 0.0, 1.0);
}

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.clipPosition  = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldPosition = worldPos.xyz;

    float3x3 normalMatrix = float3x3(uniforms.normalMatrixCol0.xyz,
                                      uniforms.normalMatrixCol1.xyz,
                                      uniforms.normalMatrixCol2.xyz);
    out.worldNormal = normalMatrix * in.normal;
    out.texCoord    = in.texCoord;
    out.color       = in.color;
    return out;
}

// ===========================================================================
// Debug mode selector — change this value to visualize different channels:
//   0 = Normal rendering (Blinn-Phong point light)
//   1 = World normals (RGB = XYZ mapped to 0..1)
//   2 = NdotL (grayscale: black=0, white=1)
//   3 = Attenuation (grayscale: black=0, white=1)
//   4 = hasTexture flag (green=1, red=0)
//   5 = Texture UV (R=u, G=v, B=0)
//   6 = Texture sample only (raw texture color, or magenta if no texture)
//   7 = Vertex color only
//   8 = Diffuse term only (diffuse * NdotL * attenuation)
//   9 = Ambient term only
// ===========================================================================
constant int DEBUG_MODE [[function_constant(0)]];

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant FragmentUniforms& fragUniforms [[buffer(0)]],
                              constant ShadowUniforms& shadowUniforms [[buffer(1)]],
                              texture2d<float> diffuseTexture [[texture(0)]],
                              texture2d_array<float> pointShadowMap [[texture(1)]],
                              sampler texSampler [[sampler(0)]],
                              sampler shadowSampler [[sampler(1)]]) {
    Light light = fragUniforms.light;
    MaterialUniforms mat = fragUniforms.material;

    float3 N = normalize(in.worldNormal);
    float3 V = normalize(fragUniforms.cameraPosition.xyz - in.worldPosition);

    // Point light
    float3 lightVec = light.positionAndRange.xyz - in.worldPosition;
    float dist = length(lightVec);
    float3 L = lightVec / dist;
    float attenuation = 1.0 / (1.0 + 0.09 * dist + 0.032 * dist * dist);
    float3 H = normalize(L + V);

    float ambientIntensity = light.colorAndAmbient.w;
    float NdotL = max(dot(N, L), 0.0);
    float shininess = mat.specular.w;
    float NdotH = max(dot(N, H), 0.0);

    float3 ambient  = mat.ambient.xyz * ambientIntensity;
    float3 diffuse  = mat.diffuse.xyz * light.colorAndAmbient.xyz * NdotL * attenuation;
    float3 specular = mat.specular.xyz * light.colorAndAmbient.xyz * pow(NdotH, shininess) * attenuation;

    float3 baseColor;
    if (mat.hasTexture) {
        baseColor = diffuseTexture.sample(texSampler, in.texCoord).rgb;
    } else {
        baseColor = in.color.rgb;
    }

    // --- Debug visualizations ---
    if (DEBUG_MODE == 1) {
        // World normals: remap [-1,1] -> [0,1]
        return float4(N * 0.5 + 0.5, 1.0);
    }
    if (DEBUG_MODE == 2) {
        // NdotL grayscale
        return float4(float3(NdotL), 1.0);
    }
    if (DEBUG_MODE == 3) {
        // Attenuation grayscale
        return float4(float3(attenuation), 1.0);
    }
    if (DEBUG_MODE == 4) {
        // hasTexture: green=yes, red=no
        if (mat.hasTexture) return float4(0, 1, 0, 1);
        else return float4(1, 0, 0, 1);
    }
    if (DEBUG_MODE == 5) {
        // UV coordinates
        return float4(in.texCoord.x, in.texCoord.y, 0, 1);
    }
    if (DEBUG_MODE == 6) {
        // Raw texture sample (magenta if no texture)
        if (mat.hasTexture) {
            return float4(diffuseTexture.sample(texSampler, in.texCoord).rgb, 1.0);
        } else {
            return float4(1, 0, 1, 1); // magenta = no texture
        }
    }
    if (DEBUG_MODE == 7) {
        // Vertex color only
        return in.color;
    }
    if (DEBUG_MODE == 8) {
        // Diffuse lighting term only
        return float4(diffuse, 1.0);
    }
    if (DEBUG_MODE == 9) {
        // Ambient term only
        return float4(ambient, 1.0);
    }

    // --- Point light shadow map array ---
    float3 lightToFragment = in.worldPosition - shadowUniforms.lightPositionAndRange.xyz;
    float currentDepth = length(lightToFragment) / shadowUniforms.lightPositionAndRange.w;
    float3 absDir = abs(lightToFragment);

    uint face = 0;
    float3 forward = float3(1.0, 0.0, 0.0);
    float3 right = float3(0.0, 0.0, -1.0);
    float3 up = float3(0.0, -1.0, 0.0);

    if (absDir.x >= absDir.y && absDir.x >= absDir.z) {
        if (lightToFragment.x >= 0.0) {
            face = 0;
            forward = float3(1.0, 0.0, 0.0);
            right = float3(0.0, 0.0, -1.0);
            up = float3(0.0, -1.0, 0.0);
        } else {
            face = 1;
            forward = float3(-1.0, 0.0, 0.0);
            right = float3(0.0, 0.0, 1.0);
            up = float3(0.0, -1.0, 0.0);
        }
    } else if (absDir.y >= absDir.z) {
        if (lightToFragment.y >= 0.0) {
            face = 2;
            forward = float3(0.0, 1.0, 0.0);
            right = float3(1.0, 0.0, 0.0);
            up = float3(0.0, 0.0, 1.0);
        } else {
            face = 3;
            forward = float3(0.0, -1.0, 0.0);
            right = float3(1.0, 0.0, 0.0);
            up = float3(0.0, 0.0, -1.0);
        }
    } else {
        if (lightToFragment.z >= 0.0) {
            face = 4;
            forward = float3(0.0, 0.0, 1.0);
            right = float3(1.0, 0.0, 0.0);
            up = float3(0.0, -1.0, 0.0);
        } else {
            face = 5;
            forward = float3(0.0, 0.0, -1.0);
            right = float3(-1.0, 0.0, 0.0);
            up = float3(0.0, -1.0, 0.0);
        }
    }

    float faceDepth = max(dot(forward, lightToFragment), 0.0001);
    float2 shadowUV = float2(dot(right, lightToFragment), -dot(up, lightToFragment)) / faceDepth;
    shadowUV = shadowUV * 0.5 + 0.5;
    float closestDepth = pointShadowMap.sample(shadowSampler, shadowUV, face).r;

    if (DEBUG_MODE == 10) {
        return float4(float3(closestDepth), 1.0);
    }

    float shadow = 1.0;
    if (shadowUniforms.shadowEnabled && mat.receivesShadow && currentDepth <= 1.0) {
        float bias = max(0.008 * (1.0 - dot(N, L)), 0.003);
        float2 texelSize = 2.5 / float2(pointShadowMap.get_width(), pointShadowMap.get_height());
        float visibility = 0.0;

        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                float2 sampleUV = shadowUV + float2(x, y) * texelSize;
                float sampleDepth = pointShadowMap.sample(shadowSampler, sampleUV, face).r;
                visibility += (currentDepth - bias > sampleDepth) ? 0.0 : 1.0;
            }
        }
        shadow = visibility / 9.0;
    }

    // Mode 0: normal rendering (with shadows)
    float3 litColor = ambient * baseColor + shadow * (diffuse * baseColor + specular);
    return float4(litColor, in.color.a);
}
