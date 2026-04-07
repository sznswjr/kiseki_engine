#pragma once

// C++ interface for the macOS window
class MacWindow {
public:
    MacWindow(int width, int height, const char* title);
    ~MacWindow();

    // Returns the CAMetalLayer* (as void* for C++ compatibility)
    void* getMetalLayer() const;

    // Process pending events. Returns false if app should quit.
    bool pollEvents();

    int getWidth() const { return m_width; }
    int getHeight() const { return m_height; }

private:
    int m_width;
    int m_height;
    void* m_window;     // NSWindow*
    void* m_metalLayer; // CAMetalLayer*
};
