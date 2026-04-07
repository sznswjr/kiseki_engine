#import <Cocoa/Cocoa.h>
#include <cstdio>
#include <string>
#include <mach-o/dyld.h>

#include "platform/MacWindow.h"
#include "renderer/MetalRenderer.h"

// ---------------------------------------------------------------------------
// Resolve path relative to the executable location
// ---------------------------------------------------------------------------
static std::string resolveShaderPath(const char* relativePath) {
    char exePath[1024];
    uint32_t size = sizeof(exePath);
    if (_NSGetExecutablePath(exePath, &size) != 0) {
        fprintf(stderr, "[KisekiEngine] Failed to get executable path\n");
        return relativePath;
    }

    std::string dir(exePath);
    auto pos = dir.find_last_of('/');
    if (pos != std::string::npos) {
        dir = dir.substr(0, pos);
    }

    return dir + "/" + relativePath;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main(int argc, const char* argv[]) {
    @autoreleasepool {
        printf("[KisekiEngine] Starting...\n");

        MacWindow window(800, 600, "KisekiEngine");

        void* metalLayer = window.getMetalLayer();
        if (!metalLayer) {
            fprintf(stderr, "[KisekiEngine] Failed to get Metal layer from window\n");
            return 1;
        }

        std::string shaderPath = resolveShaderPath("shaders/Triangle.metal");
        printf("[KisekiEngine] Shader path: %s\n", shaderPath.c_str());

        MetalRenderer renderer(metalLayer, shaderPath.c_str());
        if (!renderer.isReady()) {
            fprintf(stderr, "[KisekiEngine] Renderer initialization failed\n");
            return 1;
        }

        printf("[KisekiEngine] Entering main loop.\n");
        while (window.pollEvents()) {
            renderer.draw();
        }

        printf("[KisekiEngine] Exiting.\n");
    }
    return 0;
}
