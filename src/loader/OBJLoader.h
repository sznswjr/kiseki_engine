#pragma once

#include <vector>
#include <string>
#include "renderer/ShaderTypes.h"

class Mesh;

// Data for a single mesh group (one material)
struct OBJMeshData {
    std::vector<Vertex> vertices;
    std::vector<uint32_t> indices;
    std::string materialName;
};

// Loads .obj files and creates Mesh objects
class OBJLoader {
public:
    // Load an OBJ file and return a Mesh (uint32 indices).
    // device: id<MTLDevice> as void*
    // Returns nullptr on failure.
    static Mesh* load(const char* path, void* device);

    // Load raw vertex/index data (for custom processing)
    static bool loadRaw(const char* path,
                        std::vector<Vertex>& outVertices,
                        std::vector<uint32_t>& outIndices);

    // Load OBJ with multiple material groups
    static std::vector<OBJMeshData> loadMulti(const char* path);
};
