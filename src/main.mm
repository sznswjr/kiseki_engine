#import <Cocoa/Cocoa.h>
#include <cstdio>
#include <string>
#include <vector>
#include <cmath>
#include <mach-o/dyld.h>

#include "platform/MacWindow.h"
#include "renderer/MetalRenderer.h"
#include "renderer/Mesh.h"
#include "renderer/Texture.h"
#include "renderer/ShaderTypes.h"
#include "loader/OBJLoader.h"
#include "scene/Scene.h"
#include "core/Timer.h"
#include "core/InputManager.h"
#include "test/RenderTest.h"
#include <cstring>

// ---------------------------------------------------------------------------
// Resolve path relative to the executable location
// ---------------------------------------------------------------------------
static std::string resolvePath(const char* relativePath) {
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
// Build a unit cube mesh procedurally
// ---------------------------------------------------------------------------
static Mesh* createCubeMesh(void* device) {
    Vertex vertices[] = {
        // Front (z = +0.5)
        { { -0.5f, -0.5f,  0.5f }, { 0, 0, 1 }, { 0, 0 }, { 1, 1, 1, 1 } },
        { {  0.5f, -0.5f,  0.5f }, { 0, 0, 1 }, { 1, 0 }, { 1, 1, 1, 1 } },
        { {  0.5f,  0.5f,  0.5f }, { 0, 0, 1 }, { 1, 1 }, { 1, 1, 1, 1 } },
        { { -0.5f,  0.5f,  0.5f }, { 0, 0, 1 }, { 0, 1 }, { 1, 1, 1, 1 } },
        // Back (z = -0.5)
        { {  0.5f, -0.5f, -0.5f }, { 0, 0, -1 }, { 0, 0 }, { 1, 1, 1, 1 } },
        { { -0.5f, -0.5f, -0.5f }, { 0, 0, -1 }, { 1, 0 }, { 1, 1, 1, 1 } },
        { { -0.5f,  0.5f, -0.5f }, { 0, 0, -1 }, { 1, 1 }, { 1, 1, 1, 1 } },
        { {  0.5f,  0.5f, -0.5f }, { 0, 0, -1 }, { 0, 1 }, { 1, 1, 1, 1 } },
        // Top (y = +0.5)
        { { -0.5f,  0.5f,  0.5f }, { 0, 1, 0 }, { 0, 0 }, { 1, 1, 1, 1 } },
        { {  0.5f,  0.5f,  0.5f }, { 0, 1, 0 }, { 1, 0 }, { 1, 1, 1, 1 } },
        { {  0.5f,  0.5f, -0.5f }, { 0, 1, 0 }, { 1, 1 }, { 1, 1, 1, 1 } },
        { { -0.5f,  0.5f, -0.5f }, { 0, 1, 0 }, { 0, 1 }, { 1, 1, 1, 1 } },
        // Bottom (y = -0.5)
        { { -0.5f, -0.5f, -0.5f }, { 0, -1, 0 }, { 0, 0 }, { 1, 1, 1, 1 } },
        { {  0.5f, -0.5f, -0.5f }, { 0, -1, 0 }, { 1, 0 }, { 1, 1, 1, 1 } },
        { {  0.5f, -0.5f,  0.5f }, { 0, -1, 0 }, { 1, 1 }, { 1, 1, 1, 1 } },
        { { -0.5f, -0.5f,  0.5f }, { 0, -1, 0 }, { 0, 1 }, { 1, 1, 1, 1 } },
        // Right (x = +0.5)
        { { 0.5f, -0.5f,  0.5f }, { 1, 0, 0 }, { 0, 0 }, { 1, 1, 1, 1 } },
        { { 0.5f, -0.5f, -0.5f }, { 1, 0, 0 }, { 1, 0 }, { 1, 1, 1, 1 } },
        { { 0.5f,  0.5f, -0.5f }, { 1, 0, 0 }, { 1, 1 }, { 1, 1, 1, 1 } },
        { { 0.5f,  0.5f,  0.5f }, { 1, 0, 0 }, { 0, 1 }, { 1, 1, 1, 1 } },
        // Left (x = -0.5)
        { { -0.5f, -0.5f, -0.5f }, { -1, 0, 0 }, { 0, 0 }, { 1, 1, 1, 1 } },
        { { -0.5f, -0.5f,  0.5f }, { -1, 0, 0 }, { 1, 0 }, { 1, 1, 1, 1 } },
        { { -0.5f,  0.5f,  0.5f }, { -1, 0, 0 }, { 1, 1 }, { 1, 1, 1, 1 } },
        { { -0.5f,  0.5f, -0.5f }, { -1, 0, 0 }, { 0, 1 }, { 1, 1, 1, 1 } },
    };

    uint16_t indices[] = {
         0,  1,  2,   0,  2,  3,
         4,  5,  6,   4,  6,  7,
         8,  9, 10,   8, 10, 11,
        12, 13, 14,  12, 14, 15,
        16, 17, 18,  16, 18, 19,
        20, 21, 22,  20, 22, 23,
    };

    return new Mesh(device, vertices, sizeof(vertices), indices, 36);
}

// ---------------------------------------------------------------------------
// Build a ground plane mesh
// ---------------------------------------------------------------------------
static Mesh* createPlaneMesh(void* device, float size) {
    float h = size * 0.5f;
    Vertex vertices[] = {
        { { -h, 0, -h }, { 0, 1, 0 }, { 0, 0 },     { 0.4f, 0.4f, 0.4f, 1 } },
        { {  h, 0, -h }, { 0, 1, 0 }, { size, 0 },   { 0.4f, 0.4f, 0.4f, 1 } },
        { {  h, 0,  h }, { 0, 1, 0 }, { size, size }, { 0.4f, 0.4f, 0.4f, 1 } },
        { { -h, 0,  h }, { 0, 1, 0 }, { 0, size },   { 0.4f, 0.4f, 0.4f, 1 } },
    };
    uint16_t indices[] = { 0, 2, 1, 0, 3, 2 };
    return new Mesh(device, vertices, sizeof(vertices), indices, 6);
}

// ---------------------------------------------------------------------------
// Build a UV sphere mesh
// ---------------------------------------------------------------------------
static Mesh* createSphereMesh(void* device, float radius, int slices, int stacks) {
    std::vector<Vertex> vertices;
    std::vector<uint16_t> indices;

    for (int j = 0; j <= stacks; j++) {
        float phi = M_PI * (float)j / (float)stacks;
        float y = radius * cosf(phi);
        float r = radius * sinf(phi);

        for (int i = 0; i <= slices; i++) {
            float theta = 2.0f * M_PI * (float)i / (float)slices;
            float x = r * cosf(theta);
            float z = r * sinf(theta);

            simd_float3 pos = {x, y, z};
            simd_float3 norm = simd_normalize(pos);
            simd_float2 uv = {(float)i / slices, (float)j / stacks};

            Vertex v;
            v.position = pos;
            v.normal = norm;
            v.texCoord = uv;
            v.color = (simd_float4){1, 1, 1, 1};
            vertices.push_back(v);
        }
    }

    for (int j = 0; j < stacks; j++) {
        for (int i = 0; i < slices; i++) {
            uint16_t a = j * (slices + 1) + i;
            uint16_t b = a + (slices + 1);
            indices.push_back(a);
            indices.push_back(b);
            indices.push_back(a + 1);
            indices.push_back(a + 1);
            indices.push_back(b);
            indices.push_back(b + 1);
        }
    }

    return new Mesh(device, vertices.data(), vertices.size() * sizeof(Vertex),
                    indices.data(), indices.size());
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

        std::string shaderPath = resolvePath("shaders/Triangle.metal");
        printf("[KisekiEngine] Shader path: %s\n", shaderPath.c_str());

        MetalRenderer renderer(metalLayer, shaderPath.c_str());
        if (!renderer.isReady()) {
            fprintf(stderr, "[KisekiEngine] Renderer initialization failed\n");
            return 1;
        }

        void* device = renderer.getDevice();

        // Create meshes
        Mesh* cubeMesh   = createCubeMesh(device);
        Mesh* planeMesh  = createPlaneMesh(device, 10.0f);
        Mesh* sphereMesh = createSphereMesh(device, 0.1f, 16, 12);

        // Load OBJ model (the cube.obj from assets)
        std::string objPath = resolvePath("assets/cube.obj");
        Mesh* objMesh = OBJLoader::load(objPath.c_str(), device);

        // Build scene
        Scene scene;
        scene.camera.setPosition((simd_float3){0, 1.5f, 5});

        // Red cube (center)
        {
            SceneObject obj;
            obj.mesh = cubeMesh;
            obj.position = {0, 0.5f, 0};
            obj.material.ambient  = {0.1f, 0.02f, 0.02f};
            obj.material.diffuse  = {1.0f, 0.3f, 0.3f};
            obj.material.specular = {1.0f, 1.0f, 1.0f};
            obj.material.shininess = 64.0f;
            scene.addObject(obj);
        }

        // Blue cube (right)
        {
            SceneObject obj;
            obj.mesh = cubeMesh;
            obj.position = {2.5f, 0.5f, 0};
            obj.scaleVec = {0.7f, 0.7f, 0.7f};
            obj.material.ambient  = {0.02f, 0.02f, 0.1f};
            obj.material.diffuse  = {0.3f, 0.3f, 1.0f};
            obj.material.specular = {1.0f, 1.0f, 1.0f};
            obj.material.shininess = 128.0f;
            scene.addObject(obj);
        }

        // Green OBJ cube (left)
        if (objMesh && objMesh->isValid()) {
            SceneObject obj;
            obj.mesh = objMesh;
            obj.position = {-2.5f, 0.5f, 0};
            obj.material.ambient  = {0.02f, 0.1f, 0.02f};
            obj.material.diffuse  = {0.3f, 1.0f, 0.3f};
            obj.material.specular = {0.5f, 0.5f, 0.5f};
            obj.material.shininess = 16.0f;
            scene.addObject(obj);
        }

        // Load ground texture
        std::string groundTexPath = resolvePath("assets/ground.png");
        Texture* groundTexture = new Texture(device, groundTexPath.c_str());

        // Ground plane
        {
            SceneObject obj;
            obj.mesh = planeMesh;
            obj.position = {0, 0, 0};
            obj.material.ambient  = {0.1f, 0.1f, 0.1f};
            obj.material.diffuse  = {1.0f, 1.0f, 1.0f};
            obj.material.specular = {0.2f, 0.2f, 0.2f};
            obj.material.shininess = 8.0f;
            if (groundTexture->isValid()) {
                obj.material.diffuseTexture = groundTexture;
            }
            scene.addObject(obj);
        }

        // Light indicator sphere (emissive — bright white, ignores lighting)
        {
            SceneObject obj;
            obj.mesh = sphereMesh;
            obj.position = scene.lightPosition;
            // Use high ambient so it appears self-lit
            obj.material.ambient  = {5.0f, 5.0f, 4.0f};
            obj.material.diffuse  = {0.0f, 0.0f, 0.0f};
            obj.material.specular = {0.0f, 0.0f, 0.0f};
            obj.material.shininess = 1.0f;
            scene.addObject(obj);
        }

        // --test mode: run automated pixel tests and exit
        if (argc > 1 && strcmp(argv[1], "--test") == 0) {
            printf("[KisekiEngine] Running automated render tests...\n");
            int result = RenderTest::runAll(renderer, scene);
            return result;
        }

        Timer timer;
        int   frameCount = 0;
        float fpsTimer   = 0.0f;
        printf("[KisekiEngine] Entering main loop. WASD + mouse to navigate, ESC to quit.\n");

        while (window.pollEvents()) {
            // Pause when window is not focused
            if (!window.isFocused()) {
                // Still need to tick the timer to avoid a huge dt spike on resume
                timer.tick();
                continue;
            }

            float dt = timer.tick();
            float elapsed = timer.elapsed();

            // Handle window resize
            if (window.wasResized()) {
                renderer.handleResize();
            }

            // Debug mode: press 0-9 to switch visualization
            int numKey = InputManager::consumeNumberKeyPress();
            if (numKey >= 0) {
                renderer.setDebugMode(numKey);
            }

            // Animate the center cube
            scene.objects[0].rotation.y = elapsed;

            renderer.draw(scene, dt, elapsed);

            // FPS counter
            frameCount++;
            fpsTimer += dt;
            if (fpsTimer >= 1.0f) {
                printf("[KisekiEngine] FPS: %d\n", frameCount);
                frameCount = 0;
                fpsTimer -= 1.0f;
            }
        }

        // Cleanup
        delete cubeMesh;
        delete planeMesh;
        delete sphereMesh;
        delete objMesh;
        delete groundTexture;

        printf("[KisekiEngine] Exiting.\n");
    }
    return 0;
}
