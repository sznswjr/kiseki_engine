#pragma once

#include <simd/simd.h>
#include "renderer/Material.h"

class Mesh;

namespace kmath { simd_float4x4 translation(float, float, float); simd_float4x4 rotationX(float); simd_float4x4 rotationY(float); simd_float4x4 rotationZ(float); simd_float4x4 scale(float, float, float); }

struct SceneObject {
    Mesh*       mesh = nullptr;
    Material    material;
    simd_float3 position = {0, 0, 0};
    simd_float3 rotation = {0, 0, 0};  // Euler angles (radians)
    simd_float3 scaleVec = {1, 1, 1};
    bool castsShadow = true;
    bool receivesShadow = true;
    bool visibleInMainPass = true;
    bool visibleInShadowPass = true;

    simd_float4x4 getModelMatrix() const;
};
