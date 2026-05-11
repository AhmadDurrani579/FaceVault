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
    std::vector<float> valid;
    for (float v : depthValues) {
        if (std::isfinite(v) && v > 0.0f) {
            valid.push_back(v);
        }
    }
    
    if (valid.size() < 100) return false;
    
    // Check 1 — variance (existing)
    float variance = computeDepthVariance(valid);
    if (variance < threshold) {
        printf("[FaceVault] Lock 4 — flat surface (variance=%.6f)\n", variance);
        return false;
    }
    
    // Check 2 — depth range
    // Real face: nose to ear spread ~0.05-0.15m
    // Photo/screen: spread < 0.01m (essentially flat)
    float minDepth = *std::min_element(valid.begin(), valid.end());
    float maxDepth = *std::max_element(valid.begin(), valid.end());
    float depthRange = maxDepth - minDepth;
    
    if (depthRange < 0.02f) {
        printf("[FaceVault] Lock 4 — depth range too flat (range=%.4f)\n", depthRange);
        return false;
    }
    
    // Check 3 — nose prominence
    // Sort depth values — real face has significant near values
    // (nose tip) much closer than far values (ears/background)
    std::vector<float> sorted = valid;
    std::sort(sorted.begin(), sorted.end());
    
    // Bottom 5% should be significantly closer than top 5%
    size_t pct5 = sorted.size() * 0.05f;
    float nearMean = 0.0f, farMean = 0.0f;
    
    for (size_t i = 0; i < pct5; i++) nearMean += sorted[i];
    for (size_t i = sorted.size() - pct5; i < sorted.size(); i++) farMean += sorted[i];
    nearMean /= pct5;
    farMean  /= pct5;
    
    float prominence = farMean - nearMean;
    if (prominence < 0.03f) {
        printf("[FaceVault] Lock 4 — no nose prominence (prominence=%.4f)\n", prominence);
        return false;
    }
    
    return true;
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
//    printf("FaceVault: Raw embedding score — %f\n", result.embeddingScore);

    if (result.embeddingScore < embeddingThreshold) {
        result.rejectReason = "Embedding mismatch — identity not confirmed";
        return result;
    }
    printf("[FaceVault] Geometric RMS — %.6f (threshold=%.6f)\n",
           result.geometricScore, geometricThreshold);

    result.authenticated = true;
    result.rejectReason  = "";
    return result;
}

} // namespace facevault
