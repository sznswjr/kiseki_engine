#include "Camera.h"
#include "core/KMath.h"
#include "core/InputManager.h"
#include <cmath>

Camera::Camera()
    : m_position{0.0f, 0.0f, 3.0f}
    , m_yaw(0.0f)
    , m_pitch(0.0f)
    , m_fov(45.0f)
    , m_nearZ(0.1f)
    , m_farZ(100.0f)
    , m_moveSpeed(3.0f)
    , m_mouseSensitivity(0.003f)
{
}

void Camera::update(float dt) {
    // Mouse look
    float mdx, mdy;
    InputManager::consumeMouseDelta(mdx, mdy);
    m_yaw   += mdx * m_mouseSensitivity;
    m_pitch -= mdy * m_mouseSensitivity;

    // Clamp pitch to avoid gimbal lock
    float limit = kmath::radians(89.0f);
    if (m_pitch > limit)  m_pitch = limit;
    if (m_pitch < -limit) m_pitch = -limit;

    // Calculate forward and right vectors
    simd_float3 forward = {
        sinf(m_yaw) * cosf(m_pitch),
        sinf(m_pitch),
        -cosf(m_yaw) * cosf(m_pitch)
    };
    forward = simd_normalize(forward);

    simd_float3 worldUp = {0, 1, 0};
    simd_float3 right = simd_normalize(simd_cross(forward, worldUp));
    simd_float3 up = simd_cross(right, forward);

    // WASD movement
    float speed = m_moveSpeed * dt;
    if (InputManager::isKeyDown(InputManager::KEY_W)) m_position += forward * speed;
    if (InputManager::isKeyDown(InputManager::KEY_S)) m_position -= forward * speed;
    if (InputManager::isKeyDown(InputManager::KEY_A)) m_position -= right * speed;
    if (InputManager::isKeyDown(InputManager::KEY_D)) m_position += right * speed;
    if (InputManager::isKeyDown(InputManager::KEY_SPACE)) m_position += worldUp * speed;
    if (InputManager::isKeyDown(InputManager::KEY_SHIFT)) m_position -= worldUp * speed;
}

simd_float4x4 Camera::getViewMatrix() const {
    simd_float3 forward = {
        sinf(m_yaw) * cosf(m_pitch),
        sinf(m_pitch),
        -cosf(m_yaw) * cosf(m_pitch)
    };
    simd_float3 target = m_position + forward;
    return kmath::lookAt(m_position, target, (simd_float3){0, 1, 0});
}

simd_float4x4 Camera::getProjectionMatrix(float aspect) const {
    return kmath::perspective(kmath::radians(m_fov), aspect, m_nearZ, m_farZ);
}
