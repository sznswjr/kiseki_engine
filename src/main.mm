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
#include "loader/MTLLoader.h"
#include "loader/ProceduralMesh.h"
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
// Build a ground plane mesh (large, with tiled UVs)
// ---------------------------------------------------------------------------
static Mesh* createPlaneMesh(void* device, float size) {
    float h = size * 0.5f;
    float uvScale = size / 2.0f;
    Vertex vertices[] = {
        { { -h, 0, -h }, { 0, 1, 0 }, { 0, 0 },             { 0.4f, 0.4f, 0.4f, 1 } },
        { {  h, 0, -h }, { 0, 1, 0 }, { uvScale, 0 },        { 0.4f, 0.4f, 0.4f, 1 } },
        { {  h, 0,  h }, { 0, 1, 0 }, { uvScale, uvScale },   { 0.4f, 0.4f, 0.4f, 1 } },
        { { -h, 0,  h }, { 0, 1, 0 }, { 0, uvScale },        { 0.4f, 0.4f, 0.4f, 1 } },
    };
    uint16_t indices[] = { 0, 2, 1, 0, 3, 2 };
    return new Mesh(device, vertices, sizeof(vertices), indices, 6);
}

// ---------------------------------------------------------------------------
// Build a UV sphere mesh (for light indicator)
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
// Helper: add an OBJ model as a SceneObject with texture
// ---------------------------------------------------------------------------
static void addOBJObject(Scene& scene, Mesh* mesh, Texture* texture,
                         simd_float3 position, simd_float3 scale = {1,1,1},
                         simd_float3 rotation = {0,0,0}) {
    if (!mesh || !mesh->isValid()) return;

    SceneObject obj;
    obj.mesh = mesh;
    obj.position = position;
    obj.scaleVec = scale;
    obj.rotation = rotation;
    obj.material.ambient  = {0.15f, 0.15f, 0.15f};
    obj.material.diffuse  = {1.0f, 1.0f, 1.0f};
    obj.material.specular = {0.2f, 0.2f, 0.2f};
    obj.material.shininess = 16.0f;
    if (texture && texture->isValid()) {
        obj.material.diffuseTexture = texture;
    }
    scene.addObject(obj);
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

        // =====================================================================
        // Basic meshes
        // =====================================================================
        Mesh* planeMesh  = createPlaneMesh(device, 20.0f);
        Mesh* sphereMesh = createSphereMesh(device, 0.1f, 16, 12);

        // Procedural meshes (for rocks and bushes as fallback / supplement)
        Mesh* rockMesh = ProceduralMesh::createRock(device);

        // =====================================================================
        // Load downloaded OBJ models (Tiny Treats Homely House CC0)
        // =====================================================================
        std::string modelsDir = resolvePath("assets/models");

        auto loadModel = [&](const char* name) -> Mesh* {
            std::string path = modelsDir + "/" + name + ".obj";
            return OBJLoader::load(path.c_str(), device);
        };

        Mesh* houseMesh     = loadModel("house");
        Mesh* chimneyMesh   = loadModel("house_chimney");
        Mesh* doorMesh      = loadModel("house_door");
        Mesh* treeMesh      = loadModel("tree");
        Mesh* treeLargeMesh = loadModel("tree_large");
        Mesh* foliageAMesh  = loadModel("foliage_A");
        Mesh* foliageBMesh  = loadModel("foliage_B");
        Mesh* fenceMesh     = loadModel("fence_straight");
        Mesh* fencePostMesh = loadModel("fence_post");
        Mesh* benchMesh     = loadModel("bench_A");
        Mesh* mailboxMesh   = loadModel("mailbox");

        // =====================================================================
        // Textures
        // =====================================================================
        std::string modelTexPath = modelsDir + "/tiny_treats_texture_1.png";
        Texture* modelTexture = new Texture(device, modelTexPath.c_str());

        std::string grassTexPath = resolvePath("assets/grass.png");
        Texture* grassTexture = new Texture(device, grassTexPath.c_str());

        std::string groundTexPath = resolvePath("assets/ground.png");
        Texture* groundTexture = new Texture(device, groundTexPath.c_str());

        // =====================================================================
        // Build Scene — Garden with downloaded assets
        // =====================================================================
        Scene scene;
        scene.camera.setPosition((simd_float3){0, 3.0f, 10.0f});
        scene.lightPosition = {3.0f, 8.0f, 4.0f};
        scene.ambientIntensity = 0.2f;

        // --- Ground (grass) ---
        {
            SceneObject obj;
            obj.mesh = planeMesh;
            obj.position = {0, 0, 0};
            obj.material.ambient  = {0.1f, 0.1f, 0.1f};
            obj.material.diffuse  = {1.0f, 1.0f, 1.0f};
            obj.material.specular = {0.1f, 0.1f, 0.1f};
            obj.material.shininess = 4.0f;
            if (grassTexture->isValid()) {
                obj.material.diffuseTexture = grassTexture;
            } else if (groundTexture->isValid()) {
                obj.material.diffuseTexture = groundTexture;
            }
            scene.addObject(obj);
        }

        // --- House (center-back, assembled from parts) ---
        addOBJObject(scene, houseMesh, modelTexture, (simd_float3){0, 0, -3.0f});
        addOBJObject(scene, chimneyMesh, modelTexture, (simd_float3){0, 0, -3.0f});
        addOBJObject(scene, doorMesh, modelTexture, (simd_float3){0, 0, -3.0f});

        // --- Trees ---
        addOBJObject(scene, treeLargeMesh, modelTexture, (simd_float3){-4.5f, 0, -1.5f});
        addOBJObject(scene, treeMesh, modelTexture, (simd_float3){4.5f, 0, -2.0f});
        addOBJObject(scene, treeLargeMesh, modelTexture, (simd_float3){-6.0f, 0, 2.0f});
        addOBJObject(scene, treeMesh, modelTexture, (simd_float3){6.0f, 0, 1.0f});
        addOBJObject(scene, treeMesh, modelTexture, (simd_float3){-2.0f, 0, 5.0f});

        // --- Foliage (bushes) ---
        addOBJObject(scene, foliageAMesh, modelTexture, (simd_float3){2.5f, 0, 1.0f});
        addOBJObject(scene, foliageBMesh, modelTexture, (simd_float3){-1.5f, 0, -0.5f});
        addOBJObject(scene, foliageAMesh, modelTexture, (simd_float3){4.5f, 0, -0.5f});
        addOBJObject(scene, foliageBMesh, modelTexture, (simd_float3){-4.0f, 0, 3.5f});

        // --- Fence (south boundary) ---
        for (int i = -3; i <= 3; i++) {
            addOBJObject(scene, fenceMesh, modelTexture,
                        (simd_float3){i * 2.0f, 0, 6.5f});
        }
        // Fence posts at the ends
        addOBJObject(scene, fencePostMesh, modelTexture, (simd_float3){-7.0f, 0, 6.5f});
        addOBJObject(scene, fencePostMesh, modelTexture, (simd_float3){7.0f, 0, 6.5f});

        // --- Bench ---
        addOBJObject(scene, benchMesh, modelTexture, (simd_float3){3.0f, 0, 3.0f},
                     (simd_float3){1,1,1}, (simd_float3){0, (float)(-M_PI/4), 0});

        // --- Mailbox ---
        addOBJObject(scene, mailboxMesh, modelTexture, (simd_float3){-3.5f, 0, 5.5f});

        // --- Rocks (procedural, no texture) ---
        {
            SceneObject obj;
            obj.mesh = rockMesh;
            obj.position = {-3.0f, 0, 2.0f};
            obj.material.ambient  = {0.08f, 0.08f, 0.07f};
            obj.material.diffuse  = {0.5f, 0.48f, 0.45f};
            obj.material.specular = {0.3f, 0.3f, 0.3f};
            obj.material.shininess = 16.0f;
            scene.addObject(obj);
        }
        {
            SceneObject obj;
            obj.mesh = rockMesh;
            obj.position = {1.5f, 0, 4.0f};
            obj.scaleVec = {0.6f, 0.5f, 0.7f};
            obj.material.ambient  = {0.07f, 0.07f, 0.06f};
            obj.material.diffuse  = {0.45f, 0.43f, 0.4f};
            obj.material.specular = {0.25f, 0.25f, 0.25f};
            obj.material.shininess = 16.0f;
            scene.addObject(obj);
        }

        // --- Light indicator sphere ---
        {
            SceneObject obj;
            obj.mesh = sphereMesh;
            obj.position = scene.lightPosition;
            obj.material.ambient  = {5.0f, 5.0f, 4.0f};
            obj.material.diffuse  = {0.0f, 0.0f, 0.0f};
            obj.material.specular = {0.0f, 0.0f, 0.0f};
            obj.material.shininess = 1.0f;
            scene.addObject(obj);
        }

        printf("[KisekiEngine] Garden scene: %zu objects\n", scene.objects.size());

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
            if (!window.isFocused()) {
                timer.tick();
                continue;
            }

            float dt = timer.tick();
            float elapsed = timer.elapsed();

            if (window.wasResized()) {
                renderer.handleResize();
            }

            int numKey = InputManager::consumeNumberKeyPress();
            if (numKey >= 0) {
                renderer.setDebugMode(numKey);
            }

            renderer.draw(scene, dt, elapsed);

            frameCount++;
            fpsTimer += dt;
            if (fpsTimer >= 1.0f) {
                printf("[KisekiEngine] FPS: %d\n", frameCount);
                frameCount = 0;
                fpsTimer -= 1.0f;
            }
        }

        // Cleanup
        delete planeMesh;
        delete sphereMesh;
        delete rockMesh;
        delete houseMesh;
        delete chimneyMesh;
        delete doorMesh;
        delete treeMesh;
        delete treeLargeMesh;
        delete foliageAMesh;
        delete foliageBMesh;
        delete fenceMesh;
        delete fencePostMesh;
        delete benchMesh;
        delete mailboxMesh;
        delete modelTexture;
        delete grassTexture;
        delete groundTexture;

        printf("[KisekiEngine] Exiting.\n");
    }
    return 0;
}
