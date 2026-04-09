#pragma once

#include <vector>
#include "renderer/ShaderTypes.h"

class Mesh;

// Factory functions to generate low-poly procedural meshes.
// All functions return a Mesh* (caller owns). device = id<MTLDevice> as void*.
namespace ProceduralMesh {

    // Low-poly tree: cylinder trunk + cone canopy
    // trunkRadius, trunkHeight, canopyRadius, canopyHeight, segments
    Mesh* createTree(void* device,
                     float trunkRadius = 0.15f, float trunkHeight = 0.8f,
                     float canopyRadius = 0.6f, float canopyHeight = 1.2f,
                     int segments = 8,
                     simd_float4 trunkColor = (simd_float4){0.45f, 0.28f, 0.15f, 1.0f},
                     simd_float4 canopyColor = (simd_float4){0.2f, 0.55f, 0.15f, 1.0f});

    // Round tree: cylinder trunk + sphere canopy
    Mesh* createRoundTree(void* device,
                          float trunkRadius = 0.12f, float trunkHeight = 0.6f,
                          float canopyRadius = 0.5f,
                          int segments = 8, int rings = 5,
                          simd_float4 trunkColor = (simd_float4){0.5f, 0.3f, 0.15f, 1.0f},
                          simd_float4 canopyColor = (simd_float4){0.15f, 0.5f, 0.1f, 1.0f});

    // Simple house: box body + triangular prism roof
    Mesh* createHouse(void* device,
                      float width = 2.0f, float height = 1.5f, float depth = 2.0f,
                      float roofHeight = 0.8f,
                      simd_float4 wallColor = (simd_float4){0.85f, 0.75f, 0.6f, 1.0f},
                      simd_float4 roofColor = (simd_float4){0.65f, 0.2f, 0.15f, 1.0f});

    // Fence segment: two vertical posts + two horizontal rails
    Mesh* createFenceSegment(void* device,
                             float width = 1.5f, float height = 0.7f,
                             simd_float4 color = (simd_float4){0.6f, 0.45f, 0.25f, 1.0f});

    // Bush: flattened sphere
    Mesh* createBush(void* device,
                     float radius = 0.4f, float heightScale = 0.6f,
                     int segments = 8, int rings = 4,
                     simd_float4 color = (simd_float4){0.18f, 0.45f, 0.12f, 1.0f});

    // Rock: perturbed sphere
    Mesh* createRock(void* device,
                     float radius = 0.3f,
                     int segments = 6, int rings = 4,
                     simd_float4 color = (simd_float4){0.5f, 0.48f, 0.45f, 1.0f});
}
