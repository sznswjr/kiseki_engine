#include "InputManager.h"

bool  InputManager::s_keys[256] = {};
float InputManager::s_mouseDX = 0.0f;
float InputManager::s_mouseDY = 0.0f;

void InputManager::keyDown(uint16_t keyCode) {
    if (keyCode < 256) s_keys[keyCode] = true;
}

void InputManager::keyUp(uint16_t keyCode) {
    if (keyCode < 256) s_keys[keyCode] = false;
}

bool InputManager::isKeyDown(uint16_t keyCode) {
    return keyCode < 256 ? s_keys[keyCode] : false;
}

void InputManager::mouseMove(float dx, float dy) {
    s_mouseDX += dx;
    s_mouseDY += dy;
}

void InputManager::consumeMouseDelta(float& dx, float& dy) {
    dx = s_mouseDX;
    dy = s_mouseDY;
    s_mouseDX = 0.0f;
    s_mouseDY = 0.0f;
}
