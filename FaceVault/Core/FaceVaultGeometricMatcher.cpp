//
//  FaceVaultGeometricMatcher.cpp
//  FaceVault
//
//  Created by Ahmad on 10/04/2026.
//

#include "FaceVaultGeometricMatcher.hpp"
#include <numeric>
#include <cmath>
#include <cfloat>
#include "FaceVaultMatcher.hpp"

namespace facevault {

// Compute centroid of point cloud
simd_float3 GeometricMatcher::computeCentroid(const std::vector<simd_float3>& points) {
    simd_float3 sum = {0, 0, 0};
    for (const auto& p : points) sum += p;
    float count = static_cast<float>(points.size());
    return sum / count;
}

// Subtract centroid from all points
std::vector<simd_float3> GeometricMatcher::centerPoints(
    const std::vector<simd_float3>& points,
    simd_float3 centroid)
{
    std::vector<simd_float3> centered(points.size());
    for (size_t i = 0; i < points.size(); i++) {
        centered[i] = points[i] - centroid;
    }
    return centered;
}

// Procrustes — translate + scale only (no rotation needed
// because ARKit vertex indices are anatomically consistent)
std::vector<simd_float3> GeometricMatcher::procrustesAlign(
    const std::vector<simd_float3>& source,
    const std::vector<simd_float3>& target)
{
    if (source.size() != target.size()) return source;

    // Step 1 — centre both clouds
    simd_float3 sourceCentroid = computeCentroid(source);
    simd_float3 targetCentroid = computeCentroid(target);

    auto sourceCentered = centerPoints(source, sourceCentroid);
    auto targetCentered = centerPoints(target, targetCentroid);

    // Step 2 — compute scale ratio
    float sourceScale = 0.0f, targetScale = 0.0f;
    for (size_t i = 0; i < sourceCentered.size(); i++) {
        sourceScale += simd_dot(sourceCentered[i], sourceCentered[i]);
        targetScale += simd_dot(targetCentered[i], targetCentered[i]);
    }
    sourceScale = std::sqrt(sourceScale);
    targetScale = std::sqrt(targetScale);

    float scaleRatio = (sourceScale > 0.0f) ? (targetScale / sourceScale) : 1.0f;

    // Step 3 — apply scale + translate to target centroid
    std::vector<simd_float3> aligned(source.size());
    for (size_t i = 0; i < source.size(); i++) {
        aligned[i] = (sourceCentered[i] * scaleRatio) + targetCentroid;
    }

    return aligned;
}

std::vector<simd_float3> GeometricMatcher::extractRigidVertices(
    const std::vector<simd_float3>& points)
{
    // Forehead, nose bridge, cheekbones only
    static const std::vector<int> rigidIndices = {
        // Forehead
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
        20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        // Nose bridge
        168, 169, 170, 171, 172, 173, 174, 175,
        // Cheekbones
        234, 235, 236, 237, 238, 239,
        454, 455, 456, 457, 458, 459
    };

    std::vector<simd_float3> rigid;
    rigid.reserve(rigidIndices.size());

    for (int idx : rigidIndices) {
        if (idx < static_cast<int>(points.size())) {
            rigid.push_back(points[idx]);
        }
    }

    return rigid;
}

float GeometricMatcher::computeRMS(
    const std::vector<simd_float3>& enrolled,
    const std::vector<simd_float3>& live)
{
    if (enrolled.size() != live.size() || enrolled.empty()) return FLT_MAX;

    float sum = 0.0f;
    for (size_t i = 0; i < enrolled.size(); i++) {
        simd_float3 diff = enrolled[i] - live[i];
        sum += simd_dot(diff, diff);
    }

    return std::sqrt(sum / static_cast<float>(enrolled.size()));
}

float GeometricMatcher::computeDepthVariance(
    const std::vector<float>& depthValues)
{
    if (depthValues.empty()) return 0.0f;

    // Compute mean
    float mean = 0.0f;
    for (float v : depthValues) mean += v;
    mean /= static_cast<float>(depthValues.size());

    // Compute variance
    float variance = 0.0f;
    for (float v : depthValues) {
        float diff = v - mean;
        variance += diff * diff;
    }
    variance /= static_cast<float>(depthValues.size());

    return variance;
}

bool GeometricMatcher::isRealSkin(
    const std::vector<float>& depthValues,
    float threshold)
{
    // Filter invalid values
    std::vector<float> valid;
    for (float v : depthValues) {
        if (std::isfinite(v) && v > 0.0f) {
            valid.push_back(v);
        }
    }
    
    if (valid.empty()) return false;
    
    float variance = computeDepthVariance(valid);
    printf("FaceVault: Depth variance — %f (valid samples: %zu)\n", variance, valid.size());
    return variance > threshold;
}

AuthResult GeometricMatcher::decide(
    const std::vector<simd_float3>& enrolledMesh,
    const std::vector<simd_float3>& liveMesh,
    const std::vector<float>& depthValues,
    const std::vector<float>& enrolledEmbedding,
    const std::vector<float>& liveEmbedding,
    float geometricThreshold,
    float depthThreshold,
    float embeddingThreshold)
{
    AuthResult result;
    result.authenticated = false;

    // Gate 1 — Depth variance (photo/video/mask check)
    if (!isRealSkin(depthValues, depthThreshold)) {
        result.depthVariance = 0.0f;
        result.rejectReason = "Spoof detected — flat surface or mask";
        return result;
    }

    // Gate 2 — Geometric comparison (3D face shape check)
    auto rigidEnrolled = extractRigidVertices(enrolledMesh);
    auto rigidLive     = extractRigidVertices(liveMesh);
    auto aligned       = procrustesAlign(rigidLive, rigidEnrolled);
    result.geometricScore = computeRMS(rigidEnrolled, aligned);
    if (result.geometricScore > geometricThreshold) {
        result.rejectReason = "Geometric mismatch — wrong face shape";
        return result;
    }

    // Gate 3 — Embedding comparison (identity check)
    result.embeddingScore = facevault::Matcher::cosineSimilarity(
        enrolledEmbedding,
        liveEmbedding
    );
    printf("FaceVault: Raw embedding score — %f\n", result.embeddingScore);

    if (result.embeddingScore < embeddingThreshold) {
        result.rejectReason = "Embedding mismatch — identity not confirmed";
        return result;
    }

    // All gates passed
    result.authenticated = true;
    result.rejectReason  = "";
    return result;
}

} // namespace facevault
