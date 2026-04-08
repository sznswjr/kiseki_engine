#pragma once

#include <vector>
#include <cstdint>

struct Scene;

struct PixelRGBA {
    uint8_t r, g, b, a;
};

class MetalRenderer {
public:
    MetalRenderer(void* metalLayer, const char* shaderPath);
    ~MetalRenderer();

    bool isReady() const { return m_ready; }

    void draw(Scene& scene, float dt, float time);

    void* getDevice() const { return m_device; }

    void handleResize();

    // Debug mode: 0=normal, 1=normals, 2=NdotL, 3=attenuation,
    // 4=hasTexture, 5=UV, 6=texture, 7=vertexColor, 8=diffuse, 9=ambient
    void setDebugMode(int mode);
    int  getDebugMode() const { return m_debugMode; }

    // Render one frame offscreen and read back pixels to CPU.
    // Returns pixel buffer in RGBA order, row-major, top-to-bottom.
    std::vector<PixelRGBA> captureFrame(Scene& scene, float dt, float time,
                                         int width, int height);

    // Sample a single pixel from a captured framebuffer
    static PixelRGBA samplePixel(const std::vector<PixelRGBA>& fb,
                                  int x, int y, int width);

private:
    void createDepthTexture();
    bool createPipelineForDebugMode(int mode);

    // Shared render encoding used by both draw() and captureFrame()
    void encodeScene(void* encoder, void* ub, void* fub, Scene& scene,
                     float dt, float time, int viewWidth, int viewHeight);

    static constexpr int kMaxFramesInFlight = 3;

    bool    m_ready = false;
    int     m_debugMode = 0;
    void*   m_device = nullptr;
    void*   m_commandQueue = nullptr;
    void*   m_pipelineState = nullptr;
    void*   m_depthStencilState = nullptr;
    void*   m_uniformBuffers[kMaxFramesInFlight] = {};
    void*   m_fragUniformBuffers[kMaxFramesInFlight] = {};
    void*   m_depthTexture = nullptr;
    void*   m_samplerState = nullptr;
    void*   m_metalLayer = nullptr;
    void*   m_frameSemaphore = nullptr;
    void*   m_shaderLibrary = nullptr;
    int     m_frameIndex = 0;
};
