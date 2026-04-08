#pragma once

#include <simd/simd.h>

// This header is shared between C++/Objective-C++ code and Metal shaders.
// Use simd_float4 instead of simd_float3 + padding to ensure layout matches Metal.

struct Vertex {
    simd_float3 position;
    simd_float3 normal;
    simd_float2 texCoord;
    simd_float4 color;
};

struct Uniforms {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float4   normalMatrixCol0;
    simd_float4   normalMatrixCol1;
    simd_float4   normalMatrixCol2;
};

struct Light {
    simd_float4 position;        // xyz = world position, w = unused
    simd_float4 colorAndAmbient; // xyz = color, w = ambientIntensity
};

struct MaterialUniforms {
    simd_float4 ambient;         // xyz = ambient, w = unused
    simd_float4 diffuse;         // xyz = diffuse, w = unused
    simd_float4 specular;        // xyz = specular, w = shininess
    int         hasTexture;
    int         _pad[3];
};

struct FragmentUniforms {
    Light            light;
    MaterialUniforms material;
    simd_float4      cameraPosition; // xyz = position, w = unused
};
