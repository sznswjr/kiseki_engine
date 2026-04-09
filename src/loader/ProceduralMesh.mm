#include "ProceduralMesh.h"
#include "renderer/Mesh.h"
#include <cmath>
#include <cstdlib>

// Helper: add a box (6 faces, 24 vertices, 36 indices) with per-face normals
static void addBox(std::vector<Vertex>& verts, std::vector<uint32_t>& idxs,
                   float cx, float cy, float cz,
                   float hw, float hh, float hd,
                   simd_float4 color) {
    uint32_t base = (uint32_t)verts.size();

    // 6 faces × 4 vertices
    struct { simd_float3 n; float x[4], y[4], z[4]; } faces[6] = {
        // Front  (+Z)
        {{0,0,1},  {cx-hw, cx+hw, cx+hw, cx-hw}, {cy-hh, cy-hh, cy+hh, cy+hh}, {cz+hd, cz+hd, cz+hd, cz+hd}},
        // Back   (-Z)
        {{0,0,-1}, {cx+hw, cx-hw, cx-hw, cx+hw}, {cy-hh, cy-hh, cy+hh, cy+hh}, {cz-hd, cz-hd, cz-hd, cz-hd}},
        // Right  (+X)
        {{1,0,0},  {cx+hw, cx+hw, cx+hw, cx+hw}, {cy-hh, cy-hh, cy+hh, cy+hh}, {cz+hd, cz-hd, cz-hd, cz+hd}},
        // Left   (-X)
        {{-1,0,0}, {cx-hw, cx-hw, cx-hw, cx-hw}, {cy-hh, cy-hh, cy+hh, cy+hh}, {cz-hd, cz+hd, cz+hd, cz-hd}},
        // Top    (+Y)
        {{0,1,0},  {cx-hw, cx+hw, cx+hw, cx-hw}, {cy+hh, cy+hh, cy+hh, cy+hh}, {cz-hd, cz-hd, cz+hd, cz+hd}},
        // Bottom (-Y)
        {{0,-1,0}, {cx-hw, cx+hw, cx+hw, cx-hw}, {cy-hh, cy-hh, cy-hh, cy-hh}, {cz+hd, cz+hd, cz-hd, cz-hd}},
    };

    for (int f = 0; f < 6; f++) {
        for (int v = 0; v < 4; v++) {
            Vertex vert = {};
            vert.position = (simd_float3){faces[f].x[v], faces[f].y[v], faces[f].z[v]};
            vert.normal = faces[f].n;
            vert.texCoord = (simd_float2){(float)(v == 1 || v == 2), (float)(v == 2 || v == 3)};
            vert.color = color;
            verts.push_back(vert);
        }
        uint32_t b = base + f * 4;
        // CCW winding from outside
        idxs.push_back(b); idxs.push_back(b+1); idxs.push_back(b+2);
        idxs.push_back(b); idxs.push_back(b+2); idxs.push_back(b+3);
    }
}

// Helper: add a cone (apex at top, base at bottom)
static void addCone(std::vector<Vertex>& verts, std::vector<uint32_t>& idxs,
                    float cx, float baseY, float radius, float height,
                    int segments, simd_float4 color) {
    uint32_t apexIdx = (uint32_t)verts.size();
    float topY = baseY + height;

    // Apex vertex (will be duplicated per face for proper normals)
    // Side faces
    float slopeAngle = atan2f(radius, height);
    float ny = sinf(slopeAngle);
    float nxz = cosf(slopeAngle);

    for (int i = 0; i < segments; i++) {
        float a0 = 2.0f * M_PI * i / segments;
        float a1 = 2.0f * M_PI * (i + 1) / segments;
        float aMid = (a0 + a1) * 0.5f;

        simd_float3 n0 = {nxz * cosf(a0), ny, nxz * sinf(a0)};
        simd_float3 n1 = {nxz * cosf(a1), ny, nxz * sinf(a1)};
        simd_float3 nMid = {nxz * cosf(aMid), ny, nxz * sinf(aMid)};

        uint32_t base = (uint32_t)verts.size();

        // Apex
        Vertex va = {};
        va.position = (simd_float3){cx, topY, cx};
        va.normal = nMid;
        va.color = color;
        verts.push_back(va);

        // Base vertices
        Vertex v0 = {};
        v0.position = (simd_float3){cx + radius * cosf(a0), baseY, cx + radius * sinf(a0)};
        v0.normal = n0;
        v0.color = color;
        verts.push_back(v0);

        Vertex v1 = {};
        v1.position = (simd_float3){cx + radius * cosf(a1), baseY, cx + radius * sinf(a1)};
        v1.normal = n1;
        v1.color = color;
        verts.push_back(v1);

        idxs.push_back(base); idxs.push_back(base+2); idxs.push_back(base+1);
    }

    // Bottom cap
    uint32_t centerIdx = (uint32_t)verts.size();
    Vertex vc = {};
    vc.position = (simd_float3){cx, baseY, cx};
    vc.normal = (simd_float3){0, -1, 0};
    vc.color = color;
    verts.push_back(vc);

    for (int i = 0; i < segments; i++) {
        float a0 = 2.0f * M_PI * i / segments;
        float a1 = 2.0f * M_PI * (i + 1) / segments;

        uint32_t base = (uint32_t)verts.size();
        Vertex v0 = {}, v1 = {};
        v0.position = (simd_float3){cx + radius * cosf(a0), baseY, cx + radius * sinf(a0)};
        v0.normal = (simd_float3){0, -1, 0};
        v0.color = color;
        v1.position = (simd_float3){cx + radius * cosf(a1), baseY, cx + radius * sinf(a1)};
        v1.normal = (simd_float3){0, -1, 0};
        v1.color = color;
        verts.push_back(v0);
        verts.push_back(v1);

        idxs.push_back(centerIdx); idxs.push_back(base); idxs.push_back(base+1);
    }
}

// Helper: add a cylinder
static void addCylinder(std::vector<Vertex>& verts, std::vector<uint32_t>& idxs,
                        float cx, float baseY, float radius, float height,
                        int segments, simd_float4 color) {
    float topY = baseY + height;

    // Side faces
    for (int i = 0; i < segments; i++) {
        float a0 = 2.0f * M_PI * i / segments;
        float a1 = 2.0f * M_PI * (i + 1) / segments;

        simd_float3 n0 = {cosf(a0), 0, sinf(a0)};
        simd_float3 n1 = {cosf(a1), 0, sinf(a1)};

        uint32_t base = (uint32_t)verts.size();

        Vertex bl = {}, br = {}, tr = {}, tl = {};
        bl.position = (simd_float3){cx + radius * cosf(a0), baseY, cx + radius * sinf(a0)};
        bl.normal = n0; bl.color = color;
        br.position = (simd_float3){cx + radius * cosf(a1), baseY, cx + radius * sinf(a1)};
        br.normal = n1; br.color = color;
        tr.position = (simd_float3){cx + radius * cosf(a1), topY, cx + radius * sinf(a1)};
        tr.normal = n1; tr.color = color;
        tl.position = (simd_float3){cx + radius * cosf(a0), topY, cx + radius * sinf(a0)};
        tl.normal = n0; tl.color = color;

        verts.push_back(bl); verts.push_back(br);
        verts.push_back(tr); verts.push_back(tl);

        idxs.push_back(base); idxs.push_back(base+1); idxs.push_back(base+2);
        idxs.push_back(base); idxs.push_back(base+2); idxs.push_back(base+3);
    }
}

// Helper: add a UV sphere
static void addSphere(std::vector<Vertex>& verts, std::vector<uint32_t>& idxs,
                      float cx, float cy, float cz,
                      float rx, float ry, float rz,
                      int segments, int rings, simd_float4 color,
                      float perturbation = 0.0f) {
    // Generate vertices
    uint32_t base = (uint32_t)verts.size();

    for (int r = 0; r <= rings; r++) {
        float phi = M_PI * r / rings;
        float sinPhi = sinf(phi);
        float cosPhi = cosf(phi);

        for (int s = 0; s <= segments; s++) {
            float theta = 2.0f * M_PI * s / segments;
            float sinTheta = sinf(theta);
            float cosTheta = cosf(theta);

            simd_float3 n = {cosTheta * sinPhi, cosPhi, sinTheta * sinPhi};

            float perturb = 1.0f;
            if (perturbation > 0.0f) {
                // Deterministic pseudo-random perturbation
                perturb = 1.0f + perturbation * sinf(r * 7.3f + s * 13.7f);
            }

            Vertex v = {};
            v.position = (simd_float3){
                cx + rx * n.x * perturb,
                cy + ry * n.y * perturb,
                cz + rz * n.z * perturb
            };
            v.normal = n; // Approximate (correct for uniform sphere)
            v.texCoord = (simd_float2){(float)s / segments, (float)r / rings};
            v.color = color;
            verts.push_back(v);
        }
    }

    // Generate indices
    for (int r = 0; r < rings; r++) {
        for (int s = 0; s < segments; s++) {
            uint32_t cur = base + r * (segments + 1) + s;
            uint32_t nxt = cur + segments + 1;

            idxs.push_back(cur); idxs.push_back(cur+1); idxs.push_back(nxt);
            idxs.push_back(nxt); idxs.push_back(cur+1); idxs.push_back(nxt+1);
        }
    }
}

// Helper: create Mesh from vertex/index vectors
static Mesh* buildMesh(void* device, std::vector<Vertex>& verts, std::vector<uint32_t>& idxs) {
    return new Mesh(device,
                    verts.data(), verts.size() * sizeof(Vertex),
                    idxs.data(), idxs.size(), true);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

Mesh* ProceduralMesh::createTree(void* device,
                                  float trunkRadius, float trunkHeight,
                                  float canopyRadius, float canopyHeight,
                                  int segments,
                                  simd_float4 trunkColor, simd_float4 canopyColor) {
    std::vector<Vertex> verts;
    std::vector<uint32_t> idxs;

    addCylinder(verts, idxs, 0, 0, trunkRadius, trunkHeight, segments, trunkColor);
    addCone(verts, idxs, 0, trunkHeight, canopyRadius, canopyHeight, segments, canopyColor);

    return buildMesh(device, verts, idxs);
}

Mesh* ProceduralMesh::createRoundTree(void* device,
                                       float trunkRadius, float trunkHeight,
                                       float canopyRadius,
                                       int segments, int rings,
                                       simd_float4 trunkColor, simd_float4 canopyColor) {
    std::vector<Vertex> verts;
    std::vector<uint32_t> idxs;

    addCylinder(verts, idxs, 0, 0, trunkRadius, trunkHeight, segments, trunkColor);
    addSphere(verts, idxs, 0, trunkHeight + canopyRadius * 0.7f, 0,
              canopyRadius, canopyRadius, canopyRadius,
              segments, rings, canopyColor);

    return buildMesh(device, verts, idxs);
}

Mesh* ProceduralMesh::createHouse(void* device,
                                   float width, float height, float depth,
                                   float roofHeight,
                                   simd_float4 wallColor, simd_float4 roofColor) {
    std::vector<Vertex> verts;
    std::vector<uint32_t> idxs;

    float hw = width * 0.5f, hd = depth * 0.5f;

    // Walls (box from y=0 to y=height)
    addBox(verts, idxs, 0, height * 0.5f, 0, hw, height * 0.5f, hd, wallColor);

    // Roof (triangular prism)
    // Two triangular faces + two rectangular slopes
    float roofTop = height + roofHeight;
    float roofOverhang = 0.15f;
    float rw = hw + roofOverhang;
    float rd = hd + roofOverhang;

    uint32_t base = (uint32_t)verts.size();

    // Front triangle
    Vertex ft0 = {}, ft1 = {}, ft2 = {};
    ft0.position = (simd_float3){-rw, height, rd}; ft0.normal = (simd_float3){0, 0, 1}; ft0.color = roofColor;
    ft1.position = (simd_float3){rw, height, rd};  ft1.normal = (simd_float3){0, 0, 1}; ft1.color = roofColor;
    ft2.position = (simd_float3){0, roofTop, rd};   ft2.normal = (simd_float3){0, 0, 1}; ft2.color = roofColor;
    verts.push_back(ft0); verts.push_back(ft1); verts.push_back(ft2);
    idxs.push_back(base); idxs.push_back(base+1); idxs.push_back(base+2);

    base = (uint32_t)verts.size();
    // Back triangle
    Vertex bt0 = {}, bt1 = {}, bt2 = {};
    bt0.position = (simd_float3){rw, height, -rd};  bt0.normal = (simd_float3){0, 0, -1}; bt0.color = roofColor;
    bt1.position = (simd_float3){-rw, height, -rd}; bt1.normal = (simd_float3){0, 0, -1}; bt1.color = roofColor;
    bt2.position = (simd_float3){0, roofTop, -rd};    bt2.normal = (simd_float3){0, 0, -1}; bt2.color = roofColor;
    verts.push_back(bt0); verts.push_back(bt1); verts.push_back(bt2);
    idxs.push_back(base); idxs.push_back(base+1); idxs.push_back(base+2);

    // Left slope
    float slopeNy = rw / sqrtf(rw * rw + roofHeight * roofHeight);
    float slopeNx = roofHeight / sqrtf(rw * rw + roofHeight * roofHeight);

    base = (uint32_t)verts.size();
    simd_float3 lnorm = {-slopeNx, slopeNy, 0};
    Vertex ls0 = {}, ls1 = {}, ls2 = {}, ls3 = {};
    ls0.position = (simd_float3){-rw, height, rd};  ls0.normal = lnorm; ls0.color = roofColor;
    ls1.position = (simd_float3){-rw, height, -rd}; ls1.normal = lnorm; ls1.color = roofColor;
    ls2.position = (simd_float3){0, roofTop, -rd};    ls2.normal = lnorm; ls2.color = roofColor;
    ls3.position = (simd_float3){0, roofTop, rd};     ls3.normal = lnorm; ls3.color = roofColor;
    verts.push_back(ls0); verts.push_back(ls1); verts.push_back(ls2); verts.push_back(ls3);
    idxs.push_back(base); idxs.push_back(base+1); idxs.push_back(base+2);
    idxs.push_back(base); idxs.push_back(base+2); idxs.push_back(base+3);

    // Right slope
    base = (uint32_t)verts.size();
    simd_float3 rnorm = {slopeNx, slopeNy, 0};
    Vertex rs0 = {}, rs1 = {}, rs2 = {}, rs3 = {};
    rs0.position = (simd_float3){rw, height, -rd}; rs0.normal = rnorm; rs0.color = roofColor;
    rs1.position = (simd_float3){rw, height, rd};  rs1.normal = rnorm; rs1.color = roofColor;
    rs2.position = (simd_float3){0, roofTop, rd};    rs2.normal = rnorm; rs2.color = roofColor;
    rs3.position = (simd_float3){0, roofTop, -rd};   rs3.normal = rnorm; rs3.color = roofColor;
    verts.push_back(rs0); verts.push_back(rs1); verts.push_back(rs2); verts.push_back(rs3);
    idxs.push_back(base); idxs.push_back(base+1); idxs.push_back(base+2);
    idxs.push_back(base); idxs.push_back(base+2); idxs.push_back(base+3);

    return buildMesh(device, verts, idxs);
}

Mesh* ProceduralMesh::createFenceSegment(void* device,
                                          float width, float height,
                                          simd_float4 color) {
    std::vector<Vertex> verts;
    std::vector<uint32_t> idxs;

    float postW = 0.06f;
    float railH = 0.04f;
    float hw = width * 0.5f;

    // Two posts
    addBox(verts, idxs, -hw, height * 0.5f, 0, postW, height * 0.5f, postW, color);
    addBox(verts, idxs,  hw, height * 0.5f, 0, postW, height * 0.5f, postW, color);

    // Top rail
    addBox(verts, idxs, 0, height * 0.85f, 0, hw, railH, postW, color);
    // Bottom rail
    addBox(verts, idxs, 0, height * 0.35f, 0, hw, railH, postW, color);

    return buildMesh(device, verts, idxs);
}

Mesh* ProceduralMesh::createBush(void* device,
                                  float radius, float heightScale,
                                  int segments, int rings,
                                  simd_float4 color) {
    std::vector<Vertex> verts;
    std::vector<uint32_t> idxs;

    addSphere(verts, idxs, 0, radius * heightScale, 0,
              radius, radius * heightScale, radius,
              segments, rings, color, 0.1f);

    return buildMesh(device, verts, idxs);
}

Mesh* ProceduralMesh::createRock(void* device,
                                  float radius,
                                  int segments, int rings,
                                  simd_float4 color) {
    std::vector<Vertex> verts;
    std::vector<uint32_t> idxs;

    addSphere(verts, idxs, 0, radius * 0.6f, 0,
              radius, radius * 0.6f, radius * 0.8f,
              segments, rings, color, 0.2f);

    return buildMesh(device, verts, idxs);
}
