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

    if (!input.singleFaceDetected) {
        return DecisionResult::DeniedMultipleFaces;
    }

    if (input.landmarkCount < minLandmarks) {
        return DecisionResult::DeniedInsufficientData;
    }

    if (!input.challengePassed) {
        return DecisionResult::DeniedLiveness;
    }

    if (input.livenessScore < livenessThreshold) {
        return DecisionResult::DeniedLiveness;
    }

    if (input.embeddingScore < embeddingThreshold) {
        return DecisionResult::DeniedNoMatch;
    }

    float score = confidenceScore(input);    
    if (score >= 0.70f) {
        return DecisionResult::Authenticated;
    }

    return DecisionResult::RequiresRetry;
}
}
