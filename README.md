# KisekiEngine

A lightweight, high-performance 3D graphics engine built on Apple Metal for macOS.

![Metal](https://img.shields.io/badge/Metal-GPU-blue) ![macOS](https://img.shields.io/badge/macOS-only-lightgrey) ![C++17](https://img.shields.io/badge/C%2B%2B-17-green)

## Features

- **Blinn-Phong Lighting** — Point light with distance attenuation, ambient/diffuse/specular
- **Texture Mapping** — PNG/JPG loading via MTKTextureLoader with mipmaps, texture atlas support
- **OBJ Model Loading** — Supports v/vn/vt/f, quad triangulation, vertex deduplication, uint32 indices
- **MTL Material Parsing** — Reads .mtl files for diffuse textures (map_Kd) and material properties
- **Multi-Mesh OBJ** — Per-material mesh groups via `usemtl` directives
- **Procedural Mesh Generation** — Trees (cone/round), houses, fences, bushes, rocks
- **Fly Camera** — WASD + mouse look, Space/Shift for vertical movement
- **Scene Graph** — SceneObject with transform + material, multi-object rendering
- **Triple-Buffered Rendering** — dispatch_semaphore + 3 in-flight frames
- **Debug Visualization** — 10 shader modes (normals, NdotL, UV, texture, etc.) via keys 0-9
- **Automated Pixel Tests** — Offscreen GPU readback + 7 pixel-level render tests with adaptive calibration

## Garden Scene

The default scene is a low-poly garden featuring downloaded CC0 assets from [Tiny Treats](https://github.com/TinyTreats-Game-Assets) and procedurally generated objects:

- Textured house with chimney and door
- Two types of trees (small and large)
- Foliage bushes, fence segments, bench, mailbox
- Procedural rocks on a grass-textured ground plane
- All models share a single 1024x1024 texture atlas

## Project Structure

```
KisekiEngine/
  CMakeLists.txt
  assets/
    grass.png                # Generated grass ground texture
    ground.png               # Directional ground texture (legacy)
    cube.obj                 # Test OBJ model
    models/                  # Downloaded 3D models (Tiny Treats CC0)
      house.obj / .mtl       # House body
      house_chimney.obj      # Chimney
      house_door.obj         # Door
      tree.obj / tree_large.obj  # Trees
      foliage_A.obj / foliage_B.obj  # Bushes
      fence_straight.obj / fence_post.obj  # Fence
      bench_A.obj            # Park bench
      mailbox.obj            # Mailbox
      tiny_treats_texture_1.png  # Shared texture atlas
  shaders/
    Triangle.metal           # Blinn-Phong + 10 debug visualization modes
  src/
    main.mm                  # Entry point, garden scene setup, main loop
    core/
      KMath.h                # Math utilities (perspective, lookAt, rotations)
      InputManager.h/.mm     # Keyboard + mouse input tracking
      Timer.h                # Delta time + elapsed time
    loader/
      OBJLoader.h/.mm        # Wavefront OBJ parser (uint32, multi-mesh)
      MTLLoader.h/.mm        # MTL material file parser
      ProceduralMesh.h/.mm   # Procedural mesh generation (trees, rocks, etc.)
    platform/
      MacWindow.h/.mm        # NSWindow + CAMetalLayer + event handling
    renderer/
      MetalRenderer.h/.mm    # Core renderer, pipeline, debug modes, frame capture
      Mesh.h/.mm             # Vertex + index buffer (uint16/uint32)
      Texture.h/.mm          # MTKTextureLoader wrapper
      Material.h             # Material properties (ambient, diffuse, specular, texture)
      ShaderTypes.h          # CPU/GPU shared uniform structs
    scene/
      Camera.h/.mm           # Fly camera with yaw/pitch
      Scene.h                # Scene container (objects, light, camera)
      SceneObject.h/.mm      # Transformable object (position, rotation, scale, mesh, material)
    test/
      RenderTest.h/.mm       # Automated pixel-level render validation
```

## Build & Run

```bash
cmake -B build
cmake --build build
./build/KisekiEngine
```

## Controls

| Key | Action |
|-----|--------|
| W/A/S/D | Move forward/left/backward/right |
| Mouse | Look around |
| Space | Move up |
| Shift | Move down |
| 0-9 | Switch debug visualization mode |
| ESC | Quit |

## Debug Visualization Modes

Press number keys to switch shader output:

| Key | Mode | Description |
|-----|------|-------------|
| 0 | Normal | Standard Blinn-Phong rendering |
| 1 | Normals | World normals as RGB |
| 2 | NdotL | Lighting intensity (grayscale) |
| 3 | Attenuation | Distance falloff (grayscale) |
| 4 | hasTexture | Green = textured, Red = untextured |
| 5 | UV | Texture coordinates (R=u, G=v) |
| 6 | Texture | Raw texture sample (magenta if none) |
| 7 | Vertex Color | Raw vertex color |
| 8 | Diffuse | Diffuse lighting term only |
| 9 | Ambient | Ambient term only |

## Automated Tests

Run pixel-level render validation:

```bash
./build/KisekiEngine --test
```

The test suite renders the scene offscreen, reads back GPU pixels, and verifies:
- Background clear color
- Ground texture presence, content, normals, and lighting
- Object texture pipeline (hasTexture flag)
- Object lighting (NdotL > 0)

Tests use adaptive calibration: mode 4 (hasTexture) cross-referenced with mode 1 (normals) to accurately identify ground plane vs. 3D model pixels.

## Assets & Licensing

- **Tiny Treats Homely House** — CC0 1.0 Universal (public domain), no attribution required. Source: [TinyTreats-Game-Assets](https://github.com/TinyTreats-Game-Assets)
- **Procedural meshes** — Generated at runtime (rocks)
- **Grass texture** — Generated with Python Pillow

## Requirements

- macOS with Metal-capable GPU
- CMake 3.20+
- Xcode Command Line Tools

## Troubleshooting

- **Shader not found**: The build copies `shaders/` and `assets/` next to the executable. Run from the build output directory.
- **No Metal device**: Check with `system_profiler SPDisplaysDataType`.
- **Window not focused**: The engine pauses rendering when the window loses focus.
