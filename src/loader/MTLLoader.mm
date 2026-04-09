#include "MTLLoader.h"
#include <fstream>
#include <sstream>
#include <cstdio>

std::map<std::string, MTLMaterial> MTLLoader::load(const char* path, const std::string& baseDir) {
    std::map<std::string, MTLMaterial> materials;
    std::ifstream file(path);
    if (!file.is_open()) {
        fprintf(stderr, "[MTLLoader] Failed to open: %s\n", path);
        return materials;
    }

    MTLMaterial* current = nullptr;
    std::string line;

    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#') continue;

        std::istringstream iss(line);
        std::string token;
        iss >> token;

        if (token == "newmtl") {
            std::string name;
            iss >> name;
            materials[name] = MTLMaterial();
            materials[name].name = name;
            current = &materials[name];
        } else if (!current) {
            continue;
        } else if (token == "Kd") {
            iss >> current->Kd[0] >> current->Kd[1] >> current->Kd[2];
        } else if (token == "Ka") {
            iss >> current->Ka[0] >> current->Ka[1] >> current->Ka[2];
        } else if (token == "Ks") {
            iss >> current->Ks[0] >> current->Ks[1] >> current->Ks[2];
        } else if (token == "Ns") {
            iss >> current->Ns;
        } else if (token == "map_Kd") {
            std::string texPath;
            iss >> texPath;
            // Resolve relative to base directory
            if (!baseDir.empty() && texPath[0] != '/') {
                current->diffuseTexturePath = baseDir + "/" + texPath;
            } else {
                current->diffuseTexturePath = texPath;
            }
        }
    }

    printf("[MTLLoader] Loaded %s: %zu materials\n", path, materials.size());
    for (auto& [name, mat] : materials) {
        printf("  Material '%s': Kd=(%.2f,%.2f,%.2f)", name.c_str(), mat.Kd[0], mat.Kd[1], mat.Kd[2]);
        if (!mat.diffuseTexturePath.empty()) {
            printf(", map_Kd=%s", mat.diffuseTexturePath.c_str());
        }
        printf("\n");
    }

    return materials;
}
