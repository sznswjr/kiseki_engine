#pragma once

#include <vector>
#include <string>
#include "renderer/ShaderTypes.h"

class Mesh;

// Loads .obj files and creates Mesh objects
class OBJLoader {
public:
    // Load an OBJ file and return a Mesh.
    // device: id<MTLDevice> as void*
    // Returns nullptr on failure.
    static Mesh* load(const char* path, void* device);

    // Load raw vertex/index data (for custom processing)
    static bool loadRaw(const char* path,
                        std::vector<Vertex>& outVertices,
                        std::vector<uint16_t>& outIndices);
};
