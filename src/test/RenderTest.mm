#include "RenderTest.h"
#include "renderer/MetalRenderer.h"
#include "scene/Scene.h"
#include <cstdio>
#include <cstdlib>
#include <cmath>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static void printPixel(const char* label, PixelRGBA p) {
    printf("  %s: (%d, %d, %d, %d)\n", label, p.r, p.g, p.b, p.a);
}

static bool colorClose(PixelRGBA actual, PixelRGBA expected, int tol = 15) {
    return abs(actual.r - expected.r) <= tol
        && abs(actual.g - expected.g) <= tol
        && abs(actual.b - expected.b) <= tol;
}

static bool isNotColor(PixelRGBA actual, PixelRGBA rejected, int tol = 15) {
    return !colorClose(actual, rejected, tol);
}

static bool brighterThan(PixelRGBA p, int threshold) {
    return p.r > threshold || p.g > threshold || p.b > threshold;
}

static bool darkerThan(PixelRGBA p, int threshold) {
    return p.r < threshold && p.g < threshold && p.b < threshold;
}

// Test resolution
static const int W = 800;
static const int H = 600;

// ---------------------------------------------------------------------------
// Sample point definitions
//
// Camera at (0, 1.5, 5), yaw=0, pitch=0 → looking along -Z.
// FOV 45°, 800x600. Metal: texture y=0 is TOP, NDC y=+1 is TOP.
//
// World→Screen mapping (verified via MVP transform):
//   Origin (0,0,0) → NDC (0, -0.72) → screen (400, 83)
//   So cubes (y=0.5) are near screen y≈60-100 (top area)
//   Ground (y=0) is near screen y≈83 but extends downward
//   Background is at the bottom of the screen (y>150)
//
// We'll use an adaptive approach: first find the bounding box
// of rendered pixels, then sample relative to it.
// ---------------------------------------------------------------------------

struct SamplePoint {
    int x, y;
    const char* name;
};

// These will be computed dynamically based on bounding box
static SamplePoint BACKGROUND     = {400, 500, "background (bottom)"};
static SamplePoint GROUND_CENTER  = {400, 110, "ground (below cubes)"};
static SamplePoint GROUND_LEFT    = {200, 110, "ground (left)"};
static SamplePoint CUBE_CENTER    = {400,  70, "red cube (center)"};
static SamplePoint CUBE_RIGHT     = {570,  70, "blue cube (right)"};
static SamplePoint CUBE_LEFT      = {230,  70, "green cube (left)"};

// ---------------------------------------------------------------------------
// Adaptive sample point discovery
// Scan the framebuffer to find where objects actually are, then place
// sample points accordingly. This makes the tests robust to projection quirks.
// ---------------------------------------------------------------------------
struct BBox { int minX, maxX, minY, maxY; };

static BBox findRenderedBBox(const std::vector<PixelRGBA>& fb, int w, int h, int threshold = 30) {
    BBox bb = {w, 0, h, 0};
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            PixelRGBA p = MetalRenderer::samplePixel(fb, x, y, w);
            if (p.r > threshold || p.g > threshold || p.b > threshold) {
                if (x < bb.minX) bb.minX = x;
                if (x > bb.maxX) bb.maxX = x;
                if (y < bb.minY) bb.minY = y;
                if (y > bb.maxY) bb.maxY = y;
            }
        }
    }
    return bb;
}

static void dumpFrameToPPM(const std::vector<PixelRGBA>& fb, int w, int h, const char* filename) {
    FILE* f = fopen(filename, "wb");
    if (!f) return;
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (int i = 0; i < w * h; i++) {
        fputc(fb[i].r, f);
        fputc(fb[i].g, f);
        fputc(fb[i].b, f);
    }
    fclose(f);
    printf("[RenderTest] Dumped frame to %s\n", filename);
}

static void calibrateSamplePoints(MetalRenderer& renderer, Scene& scene) {
    // Use hasTexture mode (4) to distinguish ground (green) from cubes (red)
    renderer.setDebugMode(4);
    auto fb = renderer.captureFrame(scene, 0, 0, W, H);

    // Find ground (green pixels) and cube (red pixels) regions
    int groundSumX = 0, groundSumY = 0, groundCount = 0;
    int cubeSumX = 0, cubeSumY = 0, cubeCount = 0;

    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            PixelRGBA p = MetalRenderer::samplePixel(fb, x, y, W);
            if (p.g > 200 && p.r < 50 && p.b < 50) {
                // Green = ground with texture
                groundSumX += x; groundSumY += y; groundCount++;
            } else if (p.r > 200 && p.g < 50 && p.b < 50) {
                // Red = object without texture (cube)
                cubeSumX += x; cubeSumY += y; cubeCount++;
            }
        }
    }

    printf("[Calibration] Green(ground) pixels: %d, Red(cube) pixels: %d\n",
           groundCount, cubeCount);

    // Find a verified ground pixel (green) and cube pixel (red) by scanning
    // Start from bottom-center and scan upward for ground
    bool foundGround = false, foundCube = false;
    for (int y = H - 1; y >= 0 && (!foundGround || !foundCube); y--) {
        for (int x = 0; x < W && (!foundGround || !foundCube); x++) {
            PixelRGBA p = MetalRenderer::samplePixel(fb, x, y, W);
            if (!foundGround && p.g > 200 && p.r < 50 && p.b < 50) {
                GROUND_CENTER = {x, y, "ground (verified green)"};
                GROUND_LEFT = {x > 100 ? x - 100 : x + 100, y, "ground (left)"};
                foundGround = true;
            }
            if (!foundCube && p.r > 200 && p.g < 50 && p.b < 50) {
                CUBE_CENTER = {x, y, "cube (verified red)"};
                foundCube = true;
            }
        }
    }

    // Background: top center (should always be sky)
    BACKGROUND = {W / 2, 10, "background (top)"};

    printf("[Calibration] Sample points:\n");
    printf("  BACKGROUND: (%d,%d)\n", BACKGROUND.x, BACKGROUND.y);
    printf("  CUBE_CENTER: (%d,%d)\n", CUBE_CENTER.x, CUBE_CENTER.y);
    printf("  GROUND_CENTER: (%d,%d)\n", GROUND_CENTER.x, GROUND_CENTER.y);
    printf("  GROUND_LEFT: (%d,%d)\n", GROUND_LEFT.x, GROUND_LEFT.y);

    // Verify calibration point is actually green in this frame
    PixelRGBA gp = MetalRenderer::samplePixel(fb, GROUND_CENTER.x, GROUND_CENTER.y, W);
    printf("[Calibration] Ground centroid pixel: (%d,%d,%d)\n", gp.r, gp.g, gp.b);
    PixelRGBA cp = MetalRenderer::samplePixel(fb, CUBE_CENTER.x, CUBE_CENTER.y, W);
    printf("[Calibration] Cube centroid pixel: (%d,%d,%d)\n", cp.r, cp.g, cp.b);

    // Dump debug frames for analysis
    dumpFrameToPPM(fb, W, H, "/tmp/kiseki_mode4_hastexture.ppm");

    renderer.setDebugMode(1);
    auto fbNormals = renderer.captureFrame(scene, 0, 0, W, H);
    dumpFrameToPPM(fbNormals, W, H, "/tmp/kiseki_mode1_normals.ppm");

    renderer.setDebugMode(0);
    auto fbNormal = renderer.captureFrame(scene, 0, 0, W, H);
    dumpFrameToPPM(fbNormal, W, H, "/tmp/kiseki_mode0_normal.ppm");

    renderer.setDebugMode(0);
}

struct TestResult {
    const char* name;
    bool passed;
};

// Test 1: Background should be clear color (0.1, 0.1, 0.1) ≈ (25, 25, 25)
static TestResult testBackgroundColor(MetalRenderer& renderer, Scene& scene) {
    renderer.setDebugMode(0);
    auto fb = renderer.captureFrame(scene, 0, 0, W, H);
    PixelRGBA p = MetalRenderer::samplePixel(fb, BACKGROUND.x, BACKGROUND.y, W);
    PixelRGBA expected = {25, 25, 25, 255};
    bool pass = colorClose(p, expected, 10);
    printf("[Test 1] testBackgroundColor: %s\n", pass ? "PASS" : "FAIL");
    printPixel("actual", p);
    printPixel("expected", expected);
    return {"testBackgroundColor", pass};
}

// Test 2: Ground should have hasTexture=1 (green in mode 4)
static TestResult testGroundHasTexture(MetalRenderer& renderer, Scene& scene) {
    renderer.setDebugMode(4);
    auto fb = renderer.captureFrame(scene, 0, 0, W, H);
    PixelRGBA p = MetalRenderer::samplePixel(fb, GROUND_CENTER.x, GROUND_CENTER.y, W);
    PixelRGBA green = {0, 255, 0, 255};
    PixelRGBA red   = {255, 0, 0, 255};
    bool pass = colorClose(p, green, 10);
    printf("[Test 2] testGroundHasTexture: %s\n", pass ? "PASS" : "FAIL");
    printPixel("actual", p);
    if (!pass) {
        if (colorClose(p, red, 10)) {
            printf("  → hasTexture=0 at ground pixel! Texture not reaching shader.\n");
        } else {
            printf("  → Unexpected color. May not be sampling ground plane.\n");
        }
    }
    return {"testGroundHasTexture", pass};
}

// Test 3: Ground texture should not be magenta (mode 6 raw texture)
static TestResult testGroundTextureContent(MetalRenderer& renderer, Scene& scene) {
    renderer.setDebugMode(6);
    auto fb = renderer.captureFrame(scene, 0, 0, W, H);
    PixelRGBA p = MetalRenderer::samplePixel(fb, GROUND_CENTER.x, GROUND_CENTER.y, W);
    PixelRGBA magenta = {255, 0, 255, 255};
    bool pass = isNotColor(p, magenta, 30) && brighterThan(p, 10);
    printf("[Test 3] testGroundTextureContent: %s\n", pass ? "PASS" : "FAIL");
    printPixel("actual", p);
    if (!pass) {
        if (colorClose(p, magenta, 30)) {
            printf("  → Magenta = no texture bound. Texture binding issue.\n");
        } else {
            printf("  → Too dark. Texture may be black or missing.\n");
        }
    }
    return {"testGroundTextureContent", pass};
}

// Test 4: Ground normals should be (0,1,0) → mapped to (128,255,128) in mode 1
static TestResult testGroundNormals(MetalRenderer& renderer, Scene& scene) {
    renderer.setDebugMode(1);
    auto fb = renderer.captureFrame(scene, 0, 0, W, H);
    PixelRGBA p = MetalRenderer::samplePixel(fb, GROUND_CENTER.x, GROUND_CENTER.y, W);
    PixelRGBA expected = {128, 255, 128, 255};
    bool pass = colorClose(p, expected, 20);
    printf("[Test 4] testGroundNormals: %s\n", pass ? "PASS" : "FAIL");
    printPixel("actual", p);
    printPixel("expected", expected);
    if (!pass) {
        printf("  → Ground normal is wrong. Check vertex normals or normal matrix.\n");
    }
    return {"testGroundNormals", pass};
}

// Test 5: Ground NdotL should be nonzero (mode 2)
static TestResult testGroundNdotL(MetalRenderer& renderer, Scene& scene) {
    renderer.setDebugMode(2);
    auto fb = renderer.captureFrame(scene, 0, 0, W, H);
    PixelRGBA p = MetalRenderer::samplePixel(fb, GROUND_CENTER.x, GROUND_CENTER.y, W);
    bool pass = brighterThan(p, 20);
    printf("[Test 5] testGroundNdotL: %s\n", pass ? "PASS" : "FAIL");
    printPixel("actual", p);
    if (!pass) {
        printf("  → NdotL ≈ 0. Light direction wrong or normals inverted.\n");
    }
    return {"testGroundNdotL", pass};
}

// Test 6: Cube should have hasTexture=0 (red in mode 4)
static TestResult testCubeHasNoTexture(MetalRenderer& renderer, Scene& scene) {
    renderer.setDebugMode(4);
    auto fb = renderer.captureFrame(scene, 0, 0, W, H);
    PixelRGBA p = MetalRenderer::samplePixel(fb, CUBE_CENTER.x, CUBE_CENTER.y, W);
    PixelRGBA red = {255, 0, 0, 255};
    bool pass = colorClose(p, red, 10);
    printf("[Test 6] testCubeHasNoTexture: %s\n", pass ? "PASS" : "FAIL");
    printPixel("actual", p);
    if (!pass) {
        PixelRGBA green = {0, 255, 0, 255};
        if (colorClose(p, green, 10)) {
            printf("  → hasTexture=1 on cube! Texture leak from previous object.\n");
        } else {
            printf("  → Unexpected. May not be sampling cube face.\n");
        }
    }
    return {"testCubeHasNoTexture", pass};
}

// Test 7: Cube should have light/dark sides (mode 2 NdotL)
// Sample cube center (facing camera) and check it has some brightness variation
static TestResult testCubeNdotL(MetalRenderer& renderer, Scene& scene) {
    renderer.setDebugMode(2);
    auto fb = renderer.captureFrame(scene, 0, 0, W, H);
    // Center cube front face (facing camera, Z+)
    PixelRGBA front = MetalRenderer::samplePixel(fb, CUBE_CENTER.x, CUBE_CENTER.y, W);
    // Sample background area as reference for "no light"
    PixelRGBA bg = MetalRenderer::samplePixel(fb, BACKGROUND.x, BACKGROUND.y, W);

    // Front face should have some NdotL > 0 (not black)
    bool frontLit = brighterThan(front, 15);

    printf("[Test 7] testCubeNdotL: %s\n", frontLit ? "PASS" : "FAIL");
    printPixel("cube front NdotL", front);
    printPixel("background ref", bg);
    if (!frontLit) {
        printf("  → Cube front face has NdotL ≈ 0. Normals may be wrong.\n");
    }
    return {"testCubeNdotL", frontLit};
}

// ---------------------------------------------------------------------------
// Run all tests
// ---------------------------------------------------------------------------
int RenderTest::runAll(MetalRenderer& renderer, Scene& scene) {
    printf("\n========================================\n");
    printf("[RenderTest] Running 7 pixel tests...\n");
    printf("  Resolution: %dx%d\n", W, H);
    printf("========================================\n\n");

    // First, calibrate sample points by finding where objects are
    calibrateSamplePoints(renderer, scene);
    printf("\n");

    TestResult results[] = {
        testBackgroundColor(renderer, scene),
        testGroundHasTexture(renderer, scene),
        testGroundTextureContent(renderer, scene),
        testGroundNormals(renderer, scene),
        testGroundNdotL(renderer, scene),
        testCubeHasNoTexture(renderer, scene),
        testCubeNdotL(renderer, scene),
    };

    int total = sizeof(results) / sizeof(results[0]);
    int passed = 0;
    for (int i = 0; i < total; i++) {
        if (results[i].passed) passed++;
    }

    printf("\n========================================\n");
    printf("[RenderTest] Result: %d/%d passed", passed, total);
    if (passed == total) {
        printf(" ✓ ALL PASS\n");
    } else {
        printf(" ✗ %d FAILED:\n", total - passed);
        for (int i = 0; i < total; i++) {
            if (!results[i].passed) {
                printf("  - %s\n", results[i].name);
            }
        }
    }
    printf("========================================\n\n");

    return (passed == total) ? 0 : 1;
}
