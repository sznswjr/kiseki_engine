#pragma once

#include <cstddef>
#include <simd/simd.h>

// Mesh: owns vertex + index Metal buffers and provides draw(encoder)
class Mesh {
public:
    // Create a mesh from vertex and index data.
    // device: id<MTLDevice> as void*
    // use32BitIndices: true = uint32_t indices, false = uint16_t (default)
    Mesh(void* device, const void* vertices, size_t vertexDataSize,
         const void* indices, size_t indexCount, bool use32BitIndices = false);
    ~Mesh();

    bool isValid() const { return m_valid; }
    simd_float3 getMinBounds() const { return m_minBounds; }
    simd_float3 getMaxBounds() const { return m_maxBounds; }

    // Encode draw commands using drawIndexedPrimitives
    // encoder: id<MTLRenderCommandEncoder> as void*
    void draw(void* encoder) const;

private:
    bool   m_valid = false;
    bool   m_use32BitIndices = false;
    void*  m_vertexBuffer = nullptr;   // id<MTLBuffer>
    void*  m_indexBuffer  = nullptr;   // id<MTLBuffer>
    size_t m_indexCount    = 0;
    simd_float3 m_minBounds = {0, 0, 0};
    simd_float3 m_maxBounds = {0, 0, 0};
};
