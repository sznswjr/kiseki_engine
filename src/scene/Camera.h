#pragma once

#include <simd/simd.h>

class Camera {
public:
    Camera();

    // Call each frame with delta time to update position from input
    void update(float dt);

    simd_float4x4 getViewMatrix() const;
    simd_float4x4 getProjectionMatrix(float aspect) const;

    simd_float3 getPosition() const { return m_position; }

    void setPosition(simd_float3 pos) { m_position = pos; }
    void setFov(float fovDegrees) { m_fov = fovDegrees; }
    void setMoveSpeed(float speed) { m_moveSpeed = speed; }
    void setMouseSensitivity(float sens) { m_mouseSensitivity = sens; }

private:
    simd_float3 m_position;
    float m_yaw;    // radians, 0 = looking along -Z
    float m_pitch;  // radians, clamped to +/- ~89 degrees
    float m_fov;    // degrees
    float m_nearZ;
    float m_farZ;
    float m_moveSpeed;
    float m_mouseSensitivity;
};
