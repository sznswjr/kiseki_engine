#pragma once

#include <vector>
#include <simd/simd.h>
#include "scene/SceneObject.h"
#include "scene/Camera.h"

struct Scene {
    std::vector<SceneObject> objects;
    Camera camera;

    // Point light
    simd_float3 lightPosition   = {1.5f, 3.0f, 1.5f};  // above and to the side of center cube
    simd_float3 lightColor      = {1.0f, 1.0f, 1.0f};
    float       ambientIntensity = 0.15f;

    void addObject(const SceneObject& obj) {
        objects.push_back(obj);
    }
};
