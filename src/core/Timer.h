#pragma once

#include <chrono>

class Timer {
public:
    Timer() : m_lastTime(std::chrono::high_resolution_clock::now()) {}

    // Returns delta time in seconds since last call
    float tick() {
        auto now = std::chrono::high_resolution_clock::now();
        float dt = std::chrono::duration<float>(now - m_lastTime).count();
        m_lastTime = now;
        return dt;
    }

    // Returns elapsed time since timer creation
    float elapsed() const {
        auto now = std::chrono::high_resolution_clock::now();
        return std::chrono::duration<float>(now - m_startTime).count();
    }

private:
    std::chrono::high_resolution_clock::time_point m_startTime = std::chrono::high_resolution_clock::now();
    std::chrono::high_resolution_clock::time_point m_lastTime;
};
