#pragma once

class MacWindow {
public:
    MacWindow(int width, int height, const char* title);
    ~MacWindow();

    void* getMetalLayer() const;
    bool pollEvents();

    int getWidth() const { return m_width; }
    int getHeight() const { return m_height; }

    bool wasResized();

    // Returns true if the window is the key (focused) window
    bool isFocused() const { return m_focused; }

    // Allow MacWindow delegate to set focus state
    void setFocused(bool focused) { m_focused = focused; }

private:
    int   m_width;
    int   m_height;
    void* m_window;     // NSWindow*
    void* m_metalLayer; // CAMetalLayer*
    bool  m_resized = false;
    bool  m_focused = true;
};
