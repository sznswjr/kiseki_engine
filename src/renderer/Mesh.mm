#import "Mesh.h"
#import <Metal/Metal.h>
#include <cstdio>

Mesh::Mesh(void* device, const void* vertices, size_t vertexDataSize,
           const void* indices, size_t indexCount)
    : m_indexCount(indexCount)
{
    id<MTLDevice> dev = (__bridge id<MTLDevice>)device;

    id<MTLBuffer> vb = [dev newBufferWithBytes:vertices
                                         length:vertexDataSize
                                        options:MTLResourceStorageModeShared];
    if (!vb) {
        fprintf(stderr, "[KisekiEngine] Mesh: failed to create vertex buffer\n");
        return;
    }
    m_vertexBuffer = (__bridge_retained void*)vb;

    size_t indexDataSize = indexCount * sizeof(uint16_t);
    id<MTLBuffer> ib = [dev newBufferWithBytes:indices
                                         length:indexDataSize
                                        options:MTLResourceStorageModeShared];
    if (!ib) {
        fprintf(stderr, "[KisekiEngine] Mesh: failed to create index buffer\n");
        return;
    }
    m_indexBuffer = (__bridge_retained void*)ib;

    m_valid = true;
}

Mesh::~Mesh() {
    if (m_vertexBuffer) { CFRelease(m_vertexBuffer); m_vertexBuffer = nullptr; }
    if (m_indexBuffer)  { CFRelease(m_indexBuffer);  m_indexBuffer  = nullptr; }
}

void Mesh::draw(void* encoder) const {
    if (!m_valid) return;

    id<MTLRenderCommandEncoder> enc = (__bridge id<MTLRenderCommandEncoder>)encoder;
    id<MTLBuffer> vb = (__bridge id<MTLBuffer>)m_vertexBuffer;
    id<MTLBuffer> ib = (__bridge id<MTLBuffer>)m_indexBuffer;

    [enc setVertexBuffer:vb offset:0 atIndex:0];
    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                    indexCount:m_indexCount
                     indexType:MTLIndexTypeUInt16
                   indexBuffer:ib
             indexBufferOffset:0];
}
