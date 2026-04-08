#import "MetalRenderer.h"
#import "Mesh.h"
#import "Texture.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <dispatch/dispatch.h>
#include <simd/simd.h>
#include <cstdio>
#include <cstring>

#include "renderer/ShaderTypes.h"
#include "renderer/Material.h"
#include "core/KMath.h"
#include "scene/Scene.h"

// ---------------------------------------------------------------------------
// Helper: compile a .metal source file at runtime
// ---------------------------------------------------------------------------
static id<MTLLibrary> loadShaderLibrary(id<MTLDevice> device, const char* path) {
    NSString* shaderPath = [NSString stringWithUTF8String:path];
    NSError* error = nil;

    NSString* source = [NSString stringWithContentsOfFile:shaderPath
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
    if (!source) {
        fprintf(stderr, "[KisekiEngine] Failed to load shader file: %s\n  %s\n",
                path, [[error localizedDescription] UTF8String]);
        return nil;
    }

    MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
    id<MTLLibrary> library = [device newLibraryWithSource:source options:options error:&error];
    if (!library) {
        fprintf(stderr, "[KisekiEngine] Failed to compile shader:\n  %s\n",
                [[error localizedDescription] UTF8String]);
        return nil;
    }

    return library;
}

// ---------------------------------------------------------------------------
// MetalRenderer
// ---------------------------------------------------------------------------
MetalRenderer::MetalRenderer(void* metalLayer, const char* shaderPath)
    : m_metalLayer(metalLayer)
{
    CAMetalLayer* layer = (__bridge CAMetalLayer*)metalLayer;
    id<MTLDevice> device = layer.device;

    if (!device) {
        fprintf(stderr, "[KisekiEngine] CAMetalLayer has no device!\n");
        return;
    }
    m_device = (__bridge void*)device;

    // Command queue
    id<MTLCommandQueue> queue = [device newCommandQueue];
    if (!queue) {
        fprintf(stderr, "[KisekiEngine] Failed to create command queue\n");
        return;
    }
    m_commandQueue = (__bridge_retained void*)queue;

    // Load and compile shader
    id<MTLLibrary> library = loadShaderLibrary(device, shaderPath);
    if (!library) return;
    m_shaderLibrary = (__bridge_retained void*)library;

    // Create pipeline with debug mode 0 (normal rendering)
    if (!createPipelineForDebugMode(0)) return;

    // Depth stencil state
    MTLDepthStencilDescriptor* depthDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;
    id<MTLDepthStencilState> depthState = [device newDepthStencilStateWithDescriptor:depthDesc];
    m_depthStencilState = (__bridge_retained void*)depthState;

    // Create depth texture
    createDepthTexture();

    // Triple-buffered uniform buffers
    for (int i = 0; i < kMaxFramesInFlight; i++) {
        id<MTLBuffer> ub = [device newBufferWithLength:sizeof(Uniforms)
                                               options:MTLResourceStorageModeShared];
        m_uniformBuffers[i] = (__bridge_retained void*)ub;

        id<MTLBuffer> fub = [device newBufferWithLength:sizeof(FragmentUniforms)
                                                options:MTLResourceStorageModeShared];
        m_fragUniformBuffers[i] = (__bridge_retained void*)fub;
    }

    // Sampler state
    MTLSamplerDescriptor* samplerDesc = [[MTLSamplerDescriptor alloc] init];
    samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
    samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
    samplerDesc.mipFilter = MTLSamplerMipFilterLinear;
    samplerDesc.sAddressMode = MTLSamplerAddressModeRepeat;
    samplerDesc.tAddressMode = MTLSamplerAddressModeRepeat;
    id<MTLSamplerState> sampler = [device newSamplerStateWithDescriptor:samplerDesc];
    m_samplerState = (__bridge_retained void*)sampler;

    // Frame semaphore for triple buffering
    m_frameSemaphore = (__bridge_retained void*)dispatch_semaphore_create(kMaxFramesInFlight);

    m_ready = true;
    printf("[KisekiEngine] Renderer initialized successfully (triple-buffered).\n");
}

MetalRenderer::~MetalRenderer() {
    dispatch_semaphore_t sem = (__bridge dispatch_semaphore_t)m_frameSemaphore;
    for (int i = 0; i < kMaxFramesInFlight; i++) {
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    }

    for (int i = 0; i < kMaxFramesInFlight; i++) {
        if (m_uniformBuffers[i])     CFRelease(m_uniformBuffers[i]);
        if (m_fragUniformBuffers[i]) CFRelease(m_fragUniformBuffers[i]);
    }
    m_commandQueue      = nullptr;
    m_pipelineState     = nullptr;
    m_depthStencilState = nullptr;
    m_depthTexture      = nullptr;
    m_samplerState      = nullptr;
    m_shaderLibrary     = nullptr;
}

void MetalRenderer::createDepthTexture() {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)m_metalLayer;
    id<MTLDevice> device = (__bridge id<MTLDevice>)m_device;
    CGSize size = layer.drawableSize;

    if (size.width == 0 || size.height == 0) return;

    MTLTextureDescriptor* desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                     width:(NSUInteger)size.width
                                    height:(NSUInteger)size.height
                                 mipmapped:NO];
    desc.storageMode = MTLStorageModePrivate;
    desc.usage = MTLTextureUsageRenderTarget;

    id<MTLTexture> depthTex = [device newTextureWithDescriptor:desc];
    if (m_depthTexture) {
        CFRelease(m_depthTexture);
    }
    m_depthTexture = (__bridge_retained void*)depthTex;
}

void MetalRenderer::handleResize() {
    createDepthTexture();
}

// ---------------------------------------------------------------------------
// Shared scene encoding — used by both draw() and captureFrame()
// ---------------------------------------------------------------------------
void MetalRenderer::encodeScene(void* encoderPtr, void* ubPtr, void* fubPtr,
                                 Scene& scene, float dt, float time,
                                 int viewWidth, int viewHeight) {
    id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)encoderPtr;
    id<MTLBuffer> ub  = (__bridge id<MTLBuffer>)ubPtr;
    id<MTLBuffer> fub = (__bridge id<MTLBuffer>)fubPtr;

    id<MTLRenderPipelineState> pipeline = (__bridge id<MTLRenderPipelineState>)m_pipelineState;
    id<MTLDepthStencilState> depthState = (__bridge id<MTLDepthStencilState>)m_depthStencilState;
    id<MTLSamplerState> sampler = (__bridge id<MTLSamplerState>)m_samplerState;

    float aspect = (float)viewWidth / (float)viewHeight;
    simd_float4x4 viewMatrix = scene.camera.getViewMatrix();
    simd_float4x4 projMatrix = scene.camera.getProjectionMatrix(aspect);

    [encoder setRenderPipelineState:pipeline];
    [encoder setDepthStencilState:depthState];
    [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [encoder setCullMode:MTLCullModeBack];
    [encoder setFragmentSamplerState:sampler atIndex:0];

    // Set viewport explicitly (critical for offscreen rendering)
    MTLViewport viewport = {0, 0, (double)viewWidth, (double)viewHeight, 0, 1};
    [encoder setViewport:viewport];
    printf("[encodeScene] viewport: %dx%d\n", viewWidth, viewHeight);

    int drawCount = 0;
    for (auto& obj : scene.objects) {
        if (!obj.mesh) continue;

        simd_float4x4 modelMatrix = obj.getModelMatrix();

        Uniforms uniforms;
        uniforms.modelMatrix      = modelMatrix;
        uniforms.viewMatrix       = viewMatrix;
        uniforms.projectionMatrix = projMatrix;
        simd_float3x3 nm = simd_transpose(simd_inverse(kmath::upperLeft3x3(modelMatrix)));
        uniforms.normalMatrixCol0 = (simd_float4){nm.columns[0].x, nm.columns[0].y, nm.columns[0].z, 0};
        uniforms.normalMatrixCol1 = (simd_float4){nm.columns[1].x, nm.columns[1].y, nm.columns[1].z, 0};
        uniforms.normalMatrixCol2 = (simd_float4){nm.columns[2].x, nm.columns[2].y, nm.columns[2].z, 0};

        [encoder setVertexBytes:&uniforms length:sizeof(Uniforms) atIndex:1];

        FragmentUniforms fragUniforms;
        memset(&fragUniforms, 0, sizeof(FragmentUniforms));

        fragUniforms.light.position = (simd_float4){
            scene.lightPosition.x, scene.lightPosition.y, scene.lightPosition.z, 0};
        fragUniforms.light.colorAndAmbient = (simd_float4){
            scene.lightColor.x, scene.lightColor.y, scene.lightColor.z, scene.ambientIntensity};

        fragUniforms.material.ambient  = (simd_float4){
            obj.material.ambient.x, obj.material.ambient.y, obj.material.ambient.z, 0};
        fragUniforms.material.diffuse  = (simd_float4){
            obj.material.diffuse.x, obj.material.diffuse.y, obj.material.diffuse.z, 0};
        fragUniforms.material.specular = (simd_float4){
            obj.material.specular.x, obj.material.specular.y, obj.material.specular.z, obj.material.shininess};
        fragUniforms.material.hasTexture = obj.material.hasTexture() ? 1 : 0;

        printf("[encodeScene] obj %d: hasTexture=%d, diffuseTexPtr=%p\n",
               drawCount, fragUniforms.material.hasTexture,
               (void*)obj.material.diffuseTexture);

        simd_float3 camPos = scene.camera.getPosition();
        fragUniforms.cameraPosition = (simd_float4){camPos.x, camPos.y, camPos.z, 0};

        [encoder setFragmentBytes:&fragUniforms length:sizeof(FragmentUniforms) atIndex:0];

        if (obj.material.diffuseTexture && obj.material.diffuseTexture->isValid()) {
            id<MTLTexture> tex = (__bridge id<MTLTexture>)obj.material.diffuseTexture->getTexture();
            [encoder setFragmentTexture:tex atIndex:0];
        } else {
            [encoder setFragmentTexture:nil atIndex:0];
        }

        obj.mesh->draw((__bridge void*)encoder);
        drawCount++;
    }
    printf("[encodeScene] drew %d objects, aspect=%.2f\n", drawCount, aspect);
    printf("[encodeScene] cam pos=(%.1f,%.1f,%.1f)\n",
           scene.camera.getPosition().x, scene.camera.getPosition().y, scene.camera.getPosition().z);
    // Transform world origin through VP to verify
    simd_float4 origin = {0, 0, 0, 1};
    simd_float4 viewSpace = simd_mul(viewMatrix, origin);
    simd_float4 clipSpace = simd_mul(projMatrix, viewSpace);
    simd_float3 ndc = {clipSpace.x/clipSpace.w, clipSpace.y/clipSpace.w, clipSpace.z/clipSpace.w};
    printf("[encodeScene] origin in view=(%.2f,%.2f,%.2f,%.2f) clip=(%.2f,%.2f,%.2f,%.2f) ndc=(%.2f,%.2f,%.2f)\n",
           viewSpace.x, viewSpace.y, viewSpace.z, viewSpace.w,
           clipSpace.x, clipSpace.y, clipSpace.z, clipSpace.w,
           ndc.x, ndc.y, ndc.z);
}

// ---------------------------------------------------------------------------
// draw() — normal rendering to screen
// ---------------------------------------------------------------------------
void MetalRenderer::draw(Scene& scene, float dt, float time) {
    if (!m_ready) return;

    scene.camera.update(dt);

    dispatch_semaphore_t sem = (__bridge dispatch_semaphore_t)m_frameSemaphore;
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    int fi = m_frameIndex;
    m_frameIndex = (m_frameIndex + 1) % kMaxFramesInFlight;

    @autoreleasepool {
        CAMetalLayer* layer = (__bridge CAMetalLayer*)m_metalLayer;
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) {
            dispatch_semaphore_signal(sem);
            return;
        }

        CGSize drawableSize = layer.drawableSize;

        // Depth texture
        id<MTLTexture> depthTex = (__bridge id<MTLTexture>)m_depthTexture;

        MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
        passDesc.colorAttachments[0].texture     = drawable.texture;
        passDesc.colorAttachments[0].loadAction  = MTLLoadActionClear;
        passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
        passDesc.colorAttachments[0].clearColor  = MTLClearColorMake(0.1, 0.1, 0.1, 1.0);
        passDesc.depthAttachment.texture     = depthTex;
        passDesc.depthAttachment.loadAction  = MTLLoadActionClear;
        passDesc.depthAttachment.storeAction = MTLStoreActionDontCare;
        passDesc.depthAttachment.clearDepth  = 1.0;

        id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)m_commandQueue;
        id<MTLCommandBuffer> cmdBuffer = [queue commandBuffer];
        if (!cmdBuffer) { dispatch_semaphore_signal(sem); return; }

        [cmdBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull) {
            dispatch_semaphore_signal(sem);
        }];

        id<MTLRenderCommandEncoder> encoder = [cmdBuffer renderCommandEncoderWithDescriptor:passDesc];
        if (!encoder) { dispatch_semaphore_signal(sem); return; }

        id<MTLBuffer> ub  = (__bridge id<MTLBuffer>)m_uniformBuffers[fi];
        id<MTLBuffer> fub = (__bridge id<MTLBuffer>)m_fragUniformBuffers[fi];
        encodeScene((__bridge void*)encoder, (__bridge void*)ub, (__bridge void*)fub,
                    scene, dt, time, (int)drawableSize.width, (int)drawableSize.height);

        [encoder endEncoding];
        [cmdBuffer presentDrawable:drawable];
        [cmdBuffer commit];
    }
}

// ---------------------------------------------------------------------------
// captureFrame() — render offscreen and read back pixels
// ---------------------------------------------------------------------------
std::vector<PixelRGBA> MetalRenderer::captureFrame(Scene& scene, float dt, float time,
                                                     int width, int height) {
    std::vector<PixelRGBA> result;
    if (!m_ready) return result;

    @autoreleasepool {
        id<MTLDevice> device = (__bridge id<MTLDevice>)m_device;

        // Create offscreen color texture (Shared so CPU can read)
        MTLTextureDescriptor* colorDesc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                         width:width
                                        height:height
                                     mipmapped:NO];
        colorDesc.storageMode = MTLStorageModeShared;
        colorDesc.usage = MTLTextureUsageRenderTarget;
        id<MTLTexture> colorTex = [device newTextureWithDescriptor:colorDesc];

        // Create offscreen depth texture
        MTLTextureDescriptor* depthDesc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                         width:width
                                        height:height
                                     mipmapped:NO];
        depthDesc.storageMode = MTLStorageModePrivate;
        depthDesc.usage = MTLTextureUsageRenderTarget;
        id<MTLTexture> depthTex = [device newTextureWithDescriptor:depthDesc];

        // Render pass to offscreen textures
        MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
        passDesc.colorAttachments[0].texture     = colorTex;
        passDesc.colorAttachments[0].loadAction  = MTLLoadActionClear;
        passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
        passDesc.colorAttachments[0].clearColor  = MTLClearColorMake(0.1, 0.1, 0.1, 1.0);
        passDesc.depthAttachment.texture     = depthTex;
        passDesc.depthAttachment.loadAction  = MTLLoadActionClear;
        passDesc.depthAttachment.storeAction = MTLStoreActionDontCare;
        passDesc.depthAttachment.clearDepth  = 1.0;

        id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)m_commandQueue;
        id<MTLCommandBuffer> cmdBuffer = [queue commandBuffer];
        if (!cmdBuffer) return result;

        id<MTLRenderCommandEncoder> encoder = [cmdBuffer renderCommandEncoderWithDescriptor:passDesc];
        if (!encoder) return result;

        // Use uniform buffer 0 (this is synchronous, no triple-buffering needed)
        id<MTLBuffer> ub  = (__bridge id<MTLBuffer>)m_uniformBuffers[0];
        id<MTLBuffer> fub = (__bridge id<MTLBuffer>)m_fragUniformBuffers[0];
        encodeScene((__bridge void*)encoder, (__bridge void*)ub, (__bridge void*)fub,
                    scene, dt, time, width, height);

        [encoder endEncoding];
        [cmdBuffer commit];
        [cmdBuffer waitUntilCompleted];

        // Read back pixels (BGRA format)
        size_t bytesPerRow = width * 4;
        std::vector<uint8_t> rawPixels(bytesPerRow * height);
        [colorTex getBytes:rawPixels.data()
               bytesPerRow:bytesPerRow
                fromRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0];

        // Diagnostic: find bounding box of non-clear pixels
        int nonClearCount = 0;
        int minX = width, maxX = 0, minY = height, maxY = 0;
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int i = y * width + x;
                uint8_t b = rawPixels[i*4+0], g = rawPixels[i*4+1], r = rawPixels[i*4+2];
                if (r > 30 || g > 30 || b > 30) {
                    nonClearCount++;
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        }
        printf("[captureFrame] %dx%d, non-clear pixels: %d / %d\n",
               width, height, nonClearCount, width * height);
        if (nonClearCount > 0) {
            printf("[captureFrame] bounding box: x=[%d..%d] y=[%d..%d]\n",
                   minX, maxX, minY, maxY);
            // Sample the center of the bounding box
            int cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
            int ci = cy * width + cx;
            printf("[captureFrame] center pixel (%d,%d): BGRA=(%d,%d,%d,%d)\n",
                   cx, cy, rawPixels[ci*4], rawPixels[ci*4+1], rawPixels[ci*4+2], rawPixels[ci*4+3]);
        }

        // Convert BGRA → RGBA
        result.resize(width * height);
        for (int i = 0; i < width * height; i++) {
            result[i].r = rawPixels[i * 4 + 2]; // R from BGRA[2]
            result[i].g = rawPixels[i * 4 + 1]; // G from BGRA[1]
            result[i].b = rawPixels[i * 4 + 0]; // B from BGRA[0]
            result[i].a = rawPixels[i * 4 + 3]; // A from BGRA[3]
        }
    }

    return result;
}

PixelRGBA MetalRenderer::samplePixel(const std::vector<PixelRGBA>& fb,
                                      int x, int y, int width) {
    int idx = y * width + x;
    if (idx >= 0 && idx < (int)fb.size()) {
        return fb[idx];
    }
    return {0, 0, 0, 0};
}

// ---------------------------------------------------------------------------
// createPipelineForDebugMode / setDebugMode
// ---------------------------------------------------------------------------
bool MetalRenderer::createPipelineForDebugMode(int mode) {
    id<MTLDevice> device = (__bridge id<MTLDevice>)m_device;
    id<MTLLibrary> library = (__bridge id<MTLLibrary>)m_shaderLibrary;
    CAMetalLayer* layer = (__bridge CAMetalLayer*)m_metalLayer;

    MTLFunctionConstantValues* constants = [[MTLFunctionConstantValues alloc] init];
    [constants setConstantValue:&mode type:MTLDataTypeInt atIndex:0];

    NSError* error = nil;
    id<MTLFunction> vertexFunc = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragment_main"
                                                constantValues:constants
                                                         error:&error];
    if (!vertexFunc || !fragmentFunc) {
        fprintf(stderr, "[KisekiEngine] Failed to create shader functions for debug mode %d: %s\n",
                mode, error ? [[error localizedDescription] UTF8String] : "unknown");
        return false;
    }

    MTLVertexDescriptor* vertexDesc = [[MTLVertexDescriptor alloc] init];
    vertexDesc.attributes[0].format = MTLVertexFormatFloat3;
    vertexDesc.attributes[0].offset = offsetof(Vertex, position);
    vertexDesc.attributes[0].bufferIndex = 0;
    vertexDesc.attributes[1].format = MTLVertexFormatFloat3;
    vertexDesc.attributes[1].offset = offsetof(Vertex, normal);
    vertexDesc.attributes[1].bufferIndex = 0;
    vertexDesc.attributes[2].format = MTLVertexFormatFloat2;
    vertexDesc.attributes[2].offset = offsetof(Vertex, texCoord);
    vertexDesc.attributes[2].bufferIndex = 0;
    vertexDesc.attributes[3].format = MTLVertexFormatFloat4;
    vertexDesc.attributes[3].offset = offsetof(Vertex, color);
    vertexDesc.attributes[3].bufferIndex = 0;
    vertexDesc.layouts[0].stride = sizeof(Vertex);
    vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragmentFunc;
    pipelineDesc.vertexDescriptor = vertexDesc;
    pipelineDesc.colorAttachments[0].pixelFormat = layer.pixelFormat;
    pipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    id<MTLRenderPipelineState> pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (!pipelineState) {
        fprintf(stderr, "[KisekiEngine] Failed to create pipeline for debug mode %d: %s\n",
                mode, [[error localizedDescription] UTF8String]);
        return false;
    }

    if (m_pipelineState) {
        CFRelease(m_pipelineState);
    }
    m_pipelineState = (__bridge_retained void*)pipelineState;
    m_debugMode = mode;

    printf("[KisekiEngine] Debug mode set to %d (pipeline pixelFormat=%lu)\n",
           mode, (unsigned long)layer.pixelFormat);
    return true;
}

void MetalRenderer::setDebugMode(int mode) {
    if (mode == m_debugMode) return;
    createPipelineForDebugMode(mode);
}
