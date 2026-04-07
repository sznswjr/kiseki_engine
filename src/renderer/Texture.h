#pragma once

#include <string>

// Wraps an MTLTexture loaded from an image file
class Texture {
public:
    // Load a texture from a PNG/JPG file.
    // device: id<MTLDevice> as void*
    Texture(void* device, const char* path);
    ~Texture();

    bool isValid() const { return m_valid; }

    // Returns id<MTLTexture> as void*
    void* getTexture() const { return m_texture; }

    const std::string& getPath() const { return m_path; }

private:
    bool        m_valid = false;
    void*       m_texture = nullptr;  // id<MTLTexture>
    std::string m_path;
};
