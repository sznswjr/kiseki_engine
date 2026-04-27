#pragma once

#include <simd/simd.h>
#include <cmath>

namespace kmath {

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------
inline simd_float4x4 identity() {
    return (simd_float4x4){{
        {1, 0, 0, 0},
        {0, 1, 0, 0},
        {0, 0, 1, 0},
        {0, 0, 0, 1}
    }};
}

// ---------------------------------------------------------------------------
// Translation
// ---------------------------------------------------------------------------
inline simd_float4x4 translation(float tx, float ty, float tz) {
    simd_float4x4 m = identity();
    m.columns[3] = (simd_float4){tx, ty, tz, 1.0f};
    return m;
}

inline simd_float4x4 translation(simd_float3 t) {
    return translation(t.x, t.y, t.z);
}

// ---------------------------------------------------------------------------
// Scale
// ---------------------------------------------------------------------------
inline simd_float4x4 scale(float sx, float sy, float sz) {
    return (simd_float4x4){{
        {sx, 0,  0,  0},
        {0,  sy, 0,  0},
        {0,  0,  sz, 0},
        {0,  0,  0,  1}
    }};
}

inline simd_float4x4 scale(float s) {
    return scale(s, s, s);
}

// ---------------------------------------------------------------------------
// Rotation around X axis
// ---------------------------------------------------------------------------
inline simd_float4x4 rotationX(float radians) {
    float c = cosf(radians);
    float s = sinf(radians);
    return (simd_float4x4){{
        {1, 0,  0, 0},
        {0, c,  s, 0},
        {0, -s, c, 0},
        {0, 0,  0, 1}
    }};
}

// ---------------------------------------------------------------------------
// Rotation around Y axis
// ---------------------------------------------------------------------------
inline simd_float4x4 rotationY(float radians) {
    float c = cosf(radians);
    float s = sinf(radians);
    return (simd_float4x4){{
        {c, 0, -s, 0},
        {0, 1,  0, 0},
        {s, 0,  c, 0},
        {0, 0,  0, 1}
    }};
}

// ---------------------------------------------------------------------------
// Rotation around Z axis
// ---------------------------------------------------------------------------
inline simd_float4x4 rotationZ(float radians) {
    float c = cosf(radians);
    float s = sinf(radians);
    return (simd_float4x4){{
        { c, s, 0, 0},
        {-s, c, 0, 0},
        { 0, 0, 1, 0},
        { 0, 0, 0, 1}
    }};
}

// ---------------------------------------------------------------------------
// Perspective projection (right-handed, Metal NDC z in [0,1])
// ---------------------------------------------------------------------------
inline simd_float4x4 perspective(float fovYRadians, float aspect, float nearZ, float farZ) {
    float ys = 1.0f / tanf(fovYRadians * 0.5f);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);
    return (simd_float4x4){{
        {xs, 0,  0,           0},
        {0,  ys, 0,           0},
        {0,  0,  zs,         -1},
        {0,  0,  nearZ * zs,  0}
    }};
}

// ---------------------------------------------------------------------------
// Orthographic projection (right-handed, Metal NDC z in [0,1])
// ---------------------------------------------------------------------------
inline simd_float4x4 orthographic(float left, float right,
                                  float bottom, float top,
                                  float nearZ, float farZ) {
    float sx = 2.0f / (right - left);
    float sy = 2.0f / (top - bottom);
    float sz = 1.0f / (nearZ - farZ);
    float tx = -(right + left) / (right - left);
    float ty = -(top + bottom) / (top - bottom);
    float tz = nearZ / (nearZ - farZ);

    return (simd_float4x4){{
        {sx, 0,  0,  0},
        {0,  sy, 0,  0},
        {0,  0,  sz, 0},
        {tx, ty, tz, 1}
    }};
}

// ---------------------------------------------------------------------------
// Look-at (right-handed)
// ---------------------------------------------------------------------------
inline simd_float4x4 lookAt(simd_float3 eye, simd_float3 target, simd_float3 up) {
    simd_float3 f = simd_normalize(target - eye);
    simd_float3 s = simd_normalize(simd_cross(f, up));
    simd_float3 u = simd_cross(s, f);

    return (simd_float4x4){{
        { s.x,  u.x, -f.x, 0},
        { s.y,  u.y, -f.y, 0},
        { s.z,  u.z, -f.z, 0},
        {-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1}
    }};
}

// ---------------------------------------------------------------------------
// Extract upper-left 3x3 (for normal matrix)
// ---------------------------------------------------------------------------
inline simd_float3x3 upperLeft3x3(simd_float4x4 m) {
    return (simd_float3x3){{
        {m.columns[0].x, m.columns[0].y, m.columns[0].z},
        {m.columns[1].x, m.columns[1].y, m.columns[1].z},
        {m.columns[2].x, m.columns[2].y, m.columns[2].z}
    }};
}

// ---------------------------------------------------------------------------
// Radians conversion
// ---------------------------------------------------------------------------
inline float radians(float degrees) {
    return degrees * (M_PI / 180.0f);
}

} // namespace kmath
