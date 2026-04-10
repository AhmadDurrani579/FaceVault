//
//  FaceVaultGeometricMatcher.hpp
//  FaceVault
//
//  Created by Ahmad on 10/04/2026.
//
#pragma once
#include <vector>
#include <simd/simd.h>

namespace facevault {

struct AuthResult {
    bool authenticated;
    float geometricScore;
    float depthVariance;
    float embeddingScore;
    std::string rejectReason;
};

class GeometricMatcher {
public:
    // Step 2 — Align live mesh to enrolled mesh
    std::vector<simd_float3> procrustesAlign(
        const std::vector<simd_float3>& source,
        const std::vector<simd_float3>& target
    );
    
    // Step 3 — Extract rigid vertices only

    std::vector<simd_float3> extractRigidVertices(
        const std::vector<simd_float3>& points
    );
    
    // Step 4 — RMS geometric comparison

    float computeRMS(
        const std::vector<simd_float3>& enrolled,
        const std::vector<simd_float3>& live
    );
    
    float computeDepthVariance(
        const std::vector<float>& depthValues
    );

    bool isRealSkin(
        const std::vector<float>& depthValues,
        float threshold = 0.001f
    );


    AuthResult decide(
        const std::vector<simd_float3>& enrolledMesh,
        const std::vector<simd_float3>& liveMesh,
        const std::vector<float>& depthValues,
        const std::vector<float>& enrolledEmbedding,
        const std::vector<float>& liveEmbedding,
        float geometricThreshold  = 0.01f,
        float depthThreshold      = 0.001f,
        float embeddingThreshold  = 0.40f
    );

    
private:
    simd_float3 computeCentroid(const std::vector<simd_float3>& points);
    std::vector<simd_float3> centerPoints(
        const std::vector<simd_float3>& points,
        simd_float3 centroid
    );
};

} // namespace facevault
