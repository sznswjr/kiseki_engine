#pragma once

struct Scene;

class MetalRenderer {
public:
    MetalRenderer(void* metalLayer, const char* shaderPath);
    ~MetalRenderer();

    bool isReady() const { return m_ready; }

    void draw(Scene& scene, float dt, float time);

    void* getDevice() const { return m_device; }

    // Call when window resizes to recreate depth texture
    void handleResize();

private:
    void createDepthTexture();

    static constexpr int kMaxFramesInFlight = 3;

    bool    m_ready = false;
    void*   m_device;              // id<MTLDevice>
    void*   m_commandQueue;        // id<MTLCommandQueue>
    void*   m_pipelineState;       // id<MTLRenderPipelineState>
    void*   m_depthStencilState;   // id<MTLDepthStencilState>
    void*   m_uniformBuffers[kMaxFramesInFlight];     // id<MTLBuffer>
    void*   m_fragUniformBuffers[kMaxFramesInFlight]; // id<MTLBuffer>
    void*   m_depthTexture;        // id<MTLTexture>
    void*   m_samplerState;        // id<MTLSamplerState>
    void*   m_metalLayer;          // CAMetalLayer*
    void*   m_frameSemaphore;      // dispatch_semaphore_t
    int     m_frameIndex = 0;
};
