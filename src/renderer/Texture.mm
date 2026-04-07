#import "Texture.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include <cstdio>

Texture::Texture(void* device, const char* path) : m_path(path) {
    id<MTLDevice> dev = (__bridge id<MTLDevice>)device;

    MTKTextureLoader* loader = [[MTKTextureLoader alloc] initWithDevice:dev];

    NSString* nsPath = [NSString stringWithUTF8String:path];
    NSURL* url = [NSURL fileURLWithPath:nsPath];

    NSDictionary* options = @{
        MTKTextureLoaderOptionGenerateMipmaps: @YES,
        MTKTextureLoaderOptionSRGB: @NO
    };

    NSError* error = nil;
    id<MTLTexture> texture = [loader newTextureWithContentsOfURL:url options:options error:&error];
    if (!texture) {
        fprintf(stderr, "[Texture] Failed to load: %s\n  %s\n",
                path, [[error localizedDescription] UTF8String]);
        return;
    }

    m_texture = (__bridge_retained void*)texture;
    m_valid = true;
    printf("[Texture] Loaded: %s (%lux%lu)\n", path,
           (unsigned long)texture.width, (unsigned long)texture.height);
}

Texture::~Texture() {
    if (m_texture) {
        CFRelease(m_texture);
        m_texture = nullptr;
    }
}
