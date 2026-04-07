#include "OBJLoader.h"
#include "renderer/Mesh.h"
#include <fstream>
#include <sstream>
#include <cstdio>
#include <map>
#include <tuple>

// Key for vertex deduplication: position/texcoord/normal index triple
struct FaceVertex {
    int vi, ti, ni;
    bool operator<(const FaceVertex& o) const {
        return std::tie(vi, ti, ni) < std::tie(o.vi, o.ti, o.ni);
    }
};

bool OBJLoader::loadRaw(const char* path,
                         std::vector<Vertex>& outVertices,
                         std::vector<uint16_t>& outIndices) {
    std::ifstream file(path);
    if (!file.is_open()) {
        fprintf(stderr, "[OBJLoader] Failed to open: %s\n", path);
        return false;
    }

    std::vector<simd_float3> positions;
    std::vector<simd_float3> normals;
    std::vector<simd_float2> texCoords;
    std::map<FaceVertex, uint16_t> vertexMap;

    std::string line;
    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#') continue;

        std::istringstream iss(line);
        std::string token;
        iss >> token;

        if (token == "v") {
            float x, y, z;
            iss >> x >> y >> z;
            positions.push_back((simd_float3){x, y, z});
        } else if (token == "vn") {
            float x, y, z;
            iss >> x >> y >> z;
            normals.push_back((simd_float3){x, y, z});
        } else if (token == "vt") {
            float u, v;
            iss >> u >> v;
            texCoords.push_back((simd_float2){u, v});
        } else if (token == "f") {
            // Parse face vertices (triangulate if >3 vertices = quad)
            std::vector<FaceVertex> faceVerts;
            std::string vertStr;
            while (iss >> vertStr) {
                FaceVertex fv = {0, 0, 0};
                // Parse v, v/vt, v/vt/vn, v//vn formats
                int slashCount = 0;
                for (char c : vertStr) if (c == '/') slashCount++;

                if (slashCount == 0) {
                    sscanf(vertStr.c_str(), "%d", &fv.vi);
                } else if (slashCount == 1) {
                    sscanf(vertStr.c_str(), "%d/%d", &fv.vi, &fv.ti);
                } else if (slashCount == 2) {
                    if (vertStr.find("//") != std::string::npos) {
                        sscanf(vertStr.c_str(), "%d//%d", &fv.vi, &fv.ni);
                    } else {
                        sscanf(vertStr.c_str(), "%d/%d/%d", &fv.vi, &fv.ti, &fv.ni);
                    }
                }
                faceVerts.push_back(fv);
            }

            // Triangulate (fan from first vertex)
            for (size_t i = 1; i + 1 < faceVerts.size(); i++) {
                FaceVertex tri[3] = { faceVerts[0], faceVerts[i], faceVerts[i+1] };
                for (int j = 0; j < 3; j++) {
                    auto it = vertexMap.find(tri[j]);
                    if (it != vertexMap.end()) {
                        outIndices.push_back(it->second);
                    } else {
                        Vertex v = {};
                        if (tri[j].vi > 0 && tri[j].vi <= (int)positions.size())
                            v.position = positions[tri[j].vi - 1];
                        if (tri[j].ni > 0 && tri[j].ni <= (int)normals.size())
                            v.normal = normals[tri[j].ni - 1];
                        if (tri[j].ti > 0 && tri[j].ti <= (int)texCoords.size())
                            v.texCoord = texCoords[tri[j].ti - 1];
                        v.color = (simd_float4){0.8f, 0.8f, 0.8f, 1.0f}; // default gray

                        uint16_t idx = (uint16_t)outVertices.size();
                        vertexMap[tri[j]] = idx;
                        outVertices.push_back(v);
                        outIndices.push_back(idx);
                    }
                }
            }
        }
    }

    printf("[OBJLoader] Loaded %s: %zu vertices, %zu indices\n",
           path, outVertices.size(), outIndices.size());
    return !outVertices.empty();
}

Mesh* OBJLoader::load(const char* path, void* device) {
    std::vector<Vertex> vertices;
    std::vector<uint16_t> indices;

    if (!loadRaw(path, vertices, indices)) {
        return nullptr;
    }

    return new Mesh(device,
                    vertices.data(), vertices.size() * sizeof(Vertex),
                    indices.data(), indices.size());
}
