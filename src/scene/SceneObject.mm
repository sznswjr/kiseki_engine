#include "SceneObject.h"
#include "core/KMath.h"

simd_float4x4 SceneObject::getModelMatrix() const {
    simd_float4x4 T = kmath::translation(position.x, position.y, position.z);
    simd_float4x4 Rx = kmath::rotationX(rotation.x);
    simd_float4x4 Ry = kmath::rotationY(rotation.y);
    simd_float4x4 Rz = kmath::rotationZ(rotation.z);
    simd_float4x4 S = kmath::scale(scaleVec.x, scaleVec.y, scaleVec.z);
    return simd_mul(T, simd_mul(Rz, simd_mul(Ry, simd_mul(Rx, S))));
}
