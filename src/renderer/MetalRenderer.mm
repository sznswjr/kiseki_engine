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
    memset(m_uniformBuffers, 0, sizeof(m_uniformBuffers));
    memset(m_fragUniformBuffers, 0, sizeof(m_fragUniformBuffers));

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

    id<MTLFunction> vertexFunc   = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragment_main"];
    if (!vertexFunc || !fragmentFunc) {
        fprintf(stderr, "[KisekiEngine] Failed to find shader functions\n");
        return;
    }

    // Vertex descriptor
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

    // Pipeline
    MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragmentFunc;
    pipelineDesc.vertexDescriptor = vertexDesc;
    pipelineDesc.colorAttachments[0].pixelFormat = layer.pixelFormat;
    pipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    NSError* error = nil;
    id<MTLRenderPipelineState> pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (!pipelineState) {
        fprintf(stderr, "[KisekiEngine] Failed to create pipeline state:\n  %s\n",
                [[error localizedDescription] UTF8String]);
        return;
    }
    m_pipelineState = (__bridge_retained void*)pipelineState;

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
    // Wait for all in-flight frames to complete
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

void MetalRenderer::draw(Scene& scene, float dt, float time) {
    if (!m_ready) return;

    // Update camera
    scene.camera.update(dt);

    // Wait for a free frame slot
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
        float aspect = (float)drawableSize.width / (float)drawableSize.height;

        simd_float4x4 viewMatrix = scene.camera.getViewMatrix();
        simd_float4x4 projMatrix = scene.camera.getProjectionMatrix(aspect);

        // Render pass
        MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
        passDesc.colorAttachments[0].texture     = drawable.texture;
        passDesc.colorAttachments[0].loadAction  = MTLLoadActionClear;
        passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
        passDesc.colorAttachments[0].clearColor  = MTLClearColorMake(0.1, 0.1, 0.1, 1.0);

        id<MTLTexture> depthTex = (__bridge id<MTLTexture>)m_depthTexture;
        passDesc.depthAttachment.texture     = depthTex;
        passDesc.depthAttachment.loadAction  = MTLLoadActionClear;
        passDesc.depthAttachment.storeAction = MTLStoreActionDontCare;
        passDesc.depthAttachment.clearDepth  = 1.0;

        id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)m_commandQueue;
        id<MTLCommandBuffer> cmdBuffer = [queue commandBuffer];
        if (!cmdBuffer) {
            dispatch_semaphore_signal(sem);
            return;
        }

        // Signal semaphore when GPU finishes this frame
        [cmdBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull) {
            dispatch_semaphore_signal(sem);
        }];

        id<MTLRenderCommandEncoder> encoder = [cmdBuffer renderCommandEncoderWithDescriptor:passDesc];
        if (!encoder) {
            dispatch_semaphore_signal(sem);
            return;
        }

        id<MTLRenderPipelineState> pipeline = (__bridge id<MTLRenderPipelineState>)m_pipelineState;
        id<MTLDepthStencilState> depthState = (__bridge id<MTLDepthStencilState>)m_depthStencilState;
        id<MTLSamplerState> sampler = (__bridge id<MTLSamplerState>)m_samplerState;
        id<MTLBuffer> ub  = (__bridge id<MTLBuffer>)m_uniformBuffers[fi];
        id<MTLBuffer> fub = (__bridge id<MTLBuffer>)m_fragUniformBuffers[fi];

        [encoder setRenderPipelineState:pipeline];
        [encoder setDepthStencilState:depthState];
        [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [encoder setCullMode:MTLCullModeBack];
        [encoder setFragmentSamplerState:sampler atIndex:0];

        // Draw each object
        for (auto& obj : scene.objects) {
            if (!obj.mesh) continue;

            simd_float4x4 modelMatrix = obj.getModelMatrix();

            // Vertex uniforms
            Uniforms uniforms;
            uniforms.modelMatrix      = modelMatrix;
            uniforms.viewMatrix       = viewMatrix;
            uniforms.projectionMatrix = projMatrix;
            simd_float3x3 nm = simd_transpose(simd_inverse(kmath::upperLeft3x3(modelMatrix)));
            uniforms.normalMatrixCol0 = (simd_float4){nm.columns[0].x, nm.columns[0].y, nm.columns[0].z, 0};
            uniforms.normalMatrixCol1 = (simd_float4){nm.columns[1].x, nm.columns[1].y, nm.columns[1].z, 0};
            uniforms.normalMatrixCol2 = (simd_float4){nm.columns[2].x, nm.columns[2].y, nm.columns[2].z, 0};

            memcpy([ub contents], &uniforms, sizeof(Uniforms));
            [encoder setVertexBuffer:ub offset:0 atIndex:1];

            // Fragment uniforms
            FragmentUniforms fragUniforms;
            memset(&fragUniforms, 0, sizeof(FragmentUniforms));

            fragUniforms.light.direction = (simd_float4){
                scene.lightDirection.x, scene.lightDirection.y, scene.lightDirection.z, 0};
            fragUniforms.light.colorAndAmbient = (simd_float4){
                scene.lightColor.x, scene.lightColor.y, scene.lightColor.z, scene.ambientIntensity};

            fragUniforms.material.ambient  = (simd_float4){
                obj.material.ambient.x, obj.material.ambient.y, obj.material.ambient.z, 0};
            fragUniforms.material.diffuse  = (simd_float4){
                obj.material.diffuse.x, obj.material.diffuse.y, obj.material.diffuse.z, 0};
            fragUniforms.material.specular = (simd_float4){
                obj.material.specular.x, obj.material.specular.y, obj.material.specular.z, obj.material.shininess};
            fragUniforms.material.hasTexture = obj.material.hasTexture() ? 1 : 0;

            simd_float3 camPos = scene.camera.getPosition();
            fragUniforms.cameraPosition = (simd_float4){camPos.x, camPos.y, camPos.z, 0};

            memcpy([fub contents], &fragUniforms, sizeof(FragmentUniforms));
            [encoder setFragmentBuffer:fub offset:0 atIndex:0];

            // Bind texture if available
            if (obj.material.diffuseTexture && obj.material.diffuseTexture->isValid()) {
                id<MTLTexture> tex = (__bridge id<MTLTexture>)obj.material.diffuseTexture->getTexture();
                [encoder setFragmentTexture:tex atIndex:0];
            }

            obj.mesh->draw((__bridge void*)encoder);
        }

        [encoder endEncoding];

        [cmdBuffer presentDrawable:drawable];
        [cmdBuffer commit];
    }
}
