#pragma once

#include <simd/simd.h>

class Texture;

struct Material {
    simd_float3 ambient   = {0.1f, 0.1f, 0.1f};
    simd_float3 diffuse   = {0.8f, 0.8f, 0.8f};
    simd_float3 specular  = {1.0f, 1.0f, 1.0f};
    float       shininess = 32.0f;
    Texture*    diffuseTexture = nullptr;

    bool hasTexture() const { return diffuseTexture != nullptr; }
};
