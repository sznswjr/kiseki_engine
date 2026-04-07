#import "MetalRenderer.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <simd/simd.h>
#include <cstdio>

// Vertex layout: position (float2) + color (float4)
struct Vertex {
    simd_float2 position;
    simd_float4 color;
};

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

    id<MTLFunction> vertexFunc   = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragment_main"];
    if (!vertexFunc || !fragmentFunc) {
        fprintf(stderr, "[KisekiEngine] Failed to find shader functions\n");
        return;
    }

    // Vertex descriptor — matches the Vertex struct and shader attributes
    MTLVertexDescriptor* vertexDesc = [[MTLVertexDescriptor alloc] init];
    // attribute(0): position — float2 at offset 0
    vertexDesc.attributes[0].format = MTLVertexFormatFloat2;
    vertexDesc.attributes[0].offset = offsetof(Vertex, position);
    vertexDesc.attributes[0].bufferIndex = 0;
    // attribute(1): color — float4
    vertexDesc.attributes[1].format = MTLVertexFormatFloat4;
    vertexDesc.attributes[1].offset = offsetof(Vertex, color);
    vertexDesc.attributes[1].bufferIndex = 0;
    // layout
    vertexDesc.layouts[0].stride = sizeof(Vertex);
    vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    // Pipeline
    MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragmentFunc;
    pipelineDesc.vertexDescriptor = vertexDesc;
    pipelineDesc.colorAttachments[0].pixelFormat = layer.pixelFormat;

    NSError* error = nil;
    id<MTLRenderPipelineState> pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (!pipelineState) {
        fprintf(stderr, "[KisekiEngine] Failed to create pipeline state:\n  %s\n",
                [[error localizedDescription] UTF8String]);
        return;
    }
    m_pipelineState = (__bridge_retained void*)pipelineState;

    // Triangle vertices (clip space, y-up)
    Vertex triangleVertices[] = {
        { {  0.0f,  0.5f }, { 1.0f, 0.0f, 0.0f, 1.0f } },  // top — red
        { { -0.5f, -0.5f }, { 0.0f, 1.0f, 0.0f, 1.0f } },  // bottom-left — green
        { {  0.5f, -0.5f }, { 0.0f, 0.0f, 1.0f, 1.0f } },  // bottom-right — blue
    };
    m_vertexCount = 3;

    id<MTLBuffer> vertexBuffer = [device newBufferWithBytes:triangleVertices
                                                     length:sizeof(triangleVertices)
                                                    options:MTLResourceStorageModeShared];
    if (!vertexBuffer) {
        fprintf(stderr, "[KisekiEngine] Failed to create vertex buffer\n");
        return;
    }
    m_vertexBuffer = (__bridge_retained void*)vertexBuffer;

    m_ready = true;
    printf("[KisekiEngine] Renderer initialized successfully.\n");
}

MetalRenderer::~MetalRenderer() {
    // ARC handles release of retained ObjC objects.
    // Just clear the void* pointers.
    m_commandQueue  = nullptr;
    m_pipelineState = nullptr;
    m_vertexBuffer  = nullptr;
}

void MetalRenderer::draw() {
    if (!m_ready) return;

    @autoreleasepool {
        CAMetalLayer* layer = (__bridge CAMetalLayer*)m_metalLayer;
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) return;

        MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
        passDesc.colorAttachments[0].texture     = drawable.texture;
        passDesc.colorAttachments[0].loadAction  = MTLLoadActionClear;
        passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
        passDesc.colorAttachments[0].clearColor  = MTLClearColorMake(0.1, 0.1, 0.1, 1.0);

        id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)m_commandQueue;
        id<MTLCommandBuffer> cmdBuffer = [queue commandBuffer];
        if (!cmdBuffer) return;

        id<MTLRenderCommandEncoder> encoder = [cmdBuffer renderCommandEncoderWithDescriptor:passDesc];
        if (!encoder) return;

        id<MTLRenderPipelineState> pipeline = (__bridge id<MTLRenderPipelineState>)m_pipelineState;
        id<MTLBuffer> vb = (__bridge id<MTLBuffer>)m_vertexBuffer;

        [encoder setRenderPipelineState:pipeline];
        [encoder setVertexBuffer:vb offset:0 atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:m_vertexCount];
        [encoder endEncoding];

        [cmdBuffer presentDrawable:drawable];
        [cmdBuffer commit];
    }
}
