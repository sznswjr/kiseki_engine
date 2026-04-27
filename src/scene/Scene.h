#pragma once

#include <vector>
#include <simd/simd.h>
#include "scene/SceneObject.h"
#include "scene/Camera.h"

enum class LightType {
    Directional = 0,
    Point = 1,
    Spot = 2
};

struct SceneLight {
    LightType type = LightType::Point;
    simd_float3 position = {1.5f, 3.0f, 1.5f};
    simd_float3 direction = {0.0f, -1.0f, 0.0f};
    simd_float3 color = {1.0f, 1.0f, 1.0f};
    float intensity = 1.0f;
    float range = 30.0f;
    float ambientIntensity = 0.15f;
    float spotAngleRadians = 0.0f;
    bool castsShadow = true;
};

struct Scene {
    std::vector<SceneObject> objects;
    Camera camera;

    SceneLight light;

    void addObject(const SceneObject& obj) {
        objects.push_back(obj);
    }
};
