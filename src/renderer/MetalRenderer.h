#pragma once

class MetalRenderer {
public:
    // metalLayer: a CAMetalLayer* passed as void*
    // shaderPath: path to the .metal shader source file
    MetalRenderer(void* metalLayer, const char* shaderPath);
    ~MetalRenderer();

    bool isReady() const { return m_ready; }

    void draw();

private:
    bool m_ready = false;
    void* m_device;         // id<MTLDevice>
    void* m_commandQueue;   // id<MTLCommandQueue>
    void* m_pipelineState;  // id<MTLRenderPipelineState>
    void* m_vertexBuffer;   // id<MTLBuffer>
    void* m_metalLayer;     // CAMetalLayer*
    int   m_vertexCount = 0;
};
