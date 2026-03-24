//
//  FaceVaultDecision.hpp
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

#ifndef FaceVaultDecision_hpp
#define FaceVaultDecision_hpp

#pragma once
#include <vector>

namespace facevault {
struct DecisionInput{
    float embeddingScore;        // 0.0 - 1.0 cosine similarity
    float livenessScore;         // 0.0 - 1.0 liveness confidence
    bool challengePassed;        // ARKit challenge completed
    bool singleFaceDetected;     // only one face in frame
    int  landmarkCount;          // number of landmarks detected
};
enum class DecisionResult {
    Authenticated,
    DeniedLiveness,
    DeniedNoMatch,
    DeniedMultipleFaces,
    DeniedInsufficientData,
    RequiresRetry
};

class DecisionEngine {
public:
    float embeddingThreshold = 0.75;
    float livenessThreshold  = 0.70;
    int   minLandmarks       = 50;
    // Weights for final score
    float embeddingWeight    = 0.60f;
    float livenessWeight     = 0.40f;

    // Main decision function
    DecisionResult evaluate(const DecisionInput& input) const;

    // Final weighted confidence score
    float confidenceScore(const DecisionInput& input) const;

} ;
}
#endif /* FaceVaultDecision_hpp */
