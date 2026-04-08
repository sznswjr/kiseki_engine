cmake_minimum_required(VERSION 3.20)
project(KisekiEngine LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 17)

# --------------------------------------------------------------------------
# Sources
# --------------------------------------------------------------------------
set(SOURCES
    src/main.mm
    src/platform/MacWindow.mm
    src/renderer/MetalRenderer.mm
    src/renderer/Mesh.mm
    src/renderer/Texture.mm
    src/core/InputManager.mm
    src/scene/Camera.mm
    src/scene/SceneObject.mm
    src/loader/OBJLoader.mm
    src/test/RenderTest.mm
)

add_executable(KisekiEngine ${SOURCES})

# Enable ARC for Objective-C++
target_compile_options(KisekiEngine PRIVATE "-fobjc-arc")

# --------------------------------------------------------------------------
# Include paths
# --------------------------------------------------------------------------
target_include_directories(KisekiEngine PRIVATE ${CMAKE_SOURCE_DIR}/src)

# --------------------------------------------------------------------------
# macOS frameworks
# --------------------------------------------------------------------------
target_link_libraries(KisekiEngine PRIVATE
    "-framework Metal"
    "-framework MetalKit"
    "-framework AppKit"
    "-framework QuartzCore"
    "-framework Foundation"
)

# --------------------------------------------------------------------------
# Copy shaders next to executable for runtime loading
# --------------------------------------------------------------------------
add_custom_command(TARGET KisekiEngine POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_SOURCE_DIR}/shaders"
        "$<TARGET_FILE_DIR:KisekiEngine>/shaders"
    COMMENT "Copying shader files to build output directory"
)

add_custom_command(TARGET KisekiEngine POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_SOURCE_DIR}/assets"
        "$<TARGET_FILE_DIR:KisekiEngine>/assets"
    COMMENT "Copying asset files to build output directory"
)
