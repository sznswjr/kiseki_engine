#pragma once

#include <cstddef>

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

    // Encode draw commands using drawIndexedPrimitives
    // encoder: id<MTLRenderCommandEncoder> as void*
    void draw(void* encoder) const;

private:
    bool   m_valid = false;
    bool   m_use32BitIndices = false;
    void*  m_vertexBuffer = nullptr;   // id<MTLBuffer>
    void*  m_indexBuffer  = nullptr;   // id<MTLBuffer>
    size_t m_indexCount    = 0;
};
