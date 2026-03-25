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

    printf("C++ evaluate — embedding:%.2f liveness:%.2f challenge:%d singleFace:%d landmarks:%d\n",
           input.embeddingScore,
           input.livenessScore,
           input.challengePassed,
           input.singleFaceDetected,
           input.landmarkCount);

    if (!input.singleFaceDetected) {
        printf("C++ — rejected: no single face\n");
        return DecisionResult::DeniedMultipleFaces;
    }

    if (input.landmarkCount < minLandmarks) {
        printf("C++ — rejected: insufficient landmarks %d < %d\n", input.landmarkCount, minLandmarks);
        return DecisionResult::DeniedInsufficientData;
    }

    if (!input.challengePassed) {
        printf("C++ — rejected: challenge not passed\n");
        return DecisionResult::DeniedLiveness;
    }

    if (input.livenessScore < livenessThreshold) {
        printf("C++ — rejected: liveness score %.2f < %.2f\n", input.livenessScore, livenessThreshold);
        return DecisionResult::DeniedLiveness;
    }

    if (input.embeddingScore < embeddingThreshold) {
        printf("C++ — rejected: embedding score %.2f < %.2f\n", input.embeddingScore, embeddingThreshold);
        return DecisionResult::DeniedNoMatch;
    }

    float score = confidenceScore(input);
    printf("C++ — confidence score: %.2f\n", score);
    
    if (score >= 0.70f) {
        return DecisionResult::Authenticated;
    }

    return DecisionResult::RequiresRetry;
}
}
