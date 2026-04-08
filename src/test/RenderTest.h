#pragma once

class MetalRenderer;
struct Scene;

class RenderTest {
public:
    // Run all tests. Returns 0 if all pass, 1 if any fail.
    static int runAll(MetalRenderer& renderer, Scene& scene);
};
