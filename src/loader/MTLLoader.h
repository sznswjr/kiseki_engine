#pragma once

#include <string>
#include <map>

// Parsed material data from .mtl file
struct MTLMaterial {
    std::string name;
    std::string diffuseTexturePath;  // map_Kd path (relative to .mtl file)
    float Kd[3] = {0.8f, 0.8f, 0.8f};  // Diffuse color
    float Ka[3] = {0.1f, 0.1f, 0.1f};  // Ambient color
    float Ks[3] = {0.3f, 0.3f, 0.3f};  // Specular color
    float Ns = 32.0f;                    // Shininess
};

// Parses .mtl files and returns material name → MTLMaterial map
class MTLLoader {
public:
    // Parse a .mtl file. baseDir is used to resolve relative texture paths.
    static std::map<std::string, MTLMaterial> load(const char* path, const std::string& baseDir = "");
};
