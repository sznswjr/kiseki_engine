#pragma once

#include <vector>
#include <simd/simd.h>
#include "scene/SceneObject.h"
#include "scene/Camera.h"

struct Light;

struct Scene {
    std::vector<SceneObject> objects;
    Camera camera;

    // Directional light
    simd_float3 lightDirection = simd_normalize((simd_float3){0.5f, 1.0f, 0.8f});
    simd_float3 lightColor     = {1.0f, 1.0f, 1.0f};
    float       ambientIntensity = 0.15f;

    void addObject(const SceneObject& obj) {
        objects.push_back(obj);
    }
};
