# KisekiEngine

Minimal Metal rendering engine for macOS. First milestone: a colored triangle.

## Project Structure

```
KisekiEngine/
  CMakeLists.txt
  README.md
  src/
    main.mm              # Entry point and main loop
    platform/
      MacWindow.h        # Window interface
      MacWindow.mm       # NSWindow + CAMetalLayer creation
    renderer/
      MetalRenderer.h    # Renderer interface
      MetalRenderer.mm   # Metal init, pipeline, draw
  shaders/
    Triangle.metal       # Vertex + fragment shader
```

## Build & Run

```bash
cd KisekiEngine
cmake -B build
cmake --build build
./build/KisekiEngine
```

## Troubleshooting

- **Shader not found**: The build copies `shaders/` next to the executable. Make sure you run from the build output or the binary is in its build directory.
- **No Metal device**: Requires macOS with Metal-capable GPU. Check with `system_profiler SPDisplaysDataType`.
- **Compilation errors about ObjC**: Ensure `.mm` files and `OBJCXX` language is enabled in CMake.
