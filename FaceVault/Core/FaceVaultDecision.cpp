//
//  FaceVaultDecision.cpp
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

#include "FaceVaultDecision.hpp"

namespace facevault {

float DecisionEngine::confidenceScore(const DecisionInput& input) const {
    return  (input.embeddingScore * embeddingWeight) +
            (input.livenessScore * livenessWeight);
}
DecisionResult DecisionEngine::evaluate(const DecisionInput& input) const {
    
    // Check Single face
    if (!input.singleFaceDetected) {
        return  DecisionResult::DeniedMultipleFaces;
    }
    
    // Check landmarks
    if (input.landmarkCount < minLandmarks) {
        return  DecisionResult::DeniedInsufficientData;
    }
    
    // Check liveness first — security priority
    if(input.challengePassed) {
        return  DecisionResult::DeniedLiveness;
    }
    
    if (input.livenessScore < livenessThreshold) {
        return DecisionResult::DeniedLiveness;
    }
    
    // Check face match
    if(input.embeddingScore < embeddingThreshold) {
        return  DecisionResult::DeniedNoMatch;
    }
    
    // All checks passed
    float score = confidenceScore(input);
    
    if (score >= 0.70f) {
        return  DecisionResult::Authenticated;
    }
    return  DecisionResult::RequiresRetry;
}
}
