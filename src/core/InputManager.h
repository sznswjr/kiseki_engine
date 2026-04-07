#pragma once

#include <cstdint>

// Simple static input manager — tracks key states and mouse delta
class InputManager {
public:
    static void keyDown(uint16_t keyCode);
    static void keyUp(uint16_t keyCode);
    static bool isKeyDown(uint16_t keyCode);

    static void mouseMove(float dx, float dy);
    static void consumeMouseDelta(float& dx, float& dy);

    // macOS virtual key codes
    static constexpr uint16_t KEY_W = 13;
    static constexpr uint16_t KEY_A = 0;
    static constexpr uint16_t KEY_S = 1;
    static constexpr uint16_t KEY_D = 2;
    static constexpr uint16_t KEY_Q = 12;
    static constexpr uint16_t KEY_E = 14;
    static constexpr uint16_t KEY_SPACE = 49;
    static constexpr uint16_t KEY_SHIFT = 56;
    static constexpr uint16_t KEY_ESCAPE = 53;

private:
    static bool s_keys[256];
    static float s_mouseDX;
    static float s_mouseDY;
};
