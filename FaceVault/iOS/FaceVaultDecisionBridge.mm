//
//  FaceVaultDecisionBridge.m
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

#import <Foundation/Foundation.h>
#import "FaceVaultDecisionBridge.h"
#include "FaceVaultDecision.hpp"

@implementation FaceVaultDecisionInput
@end

@implementation FaceVaultDecisionBridge

- (NSInteger)evaluate:(FaceVaultDecisionInput *)input {
    facevault::DecisionInput cInput;
    cInput.embeddingScore     = input.embeddingScore;
    cInput.livenessScore      = input.livenessScore;
    cInput.challengePassed    = (bool)(input.challengePassed == YES);
    cInput.singleFaceDetected = (bool)(input.singleFaceDetected == YES);
    cInput.landmarkCount      = input.landmarkCount;
    
    facevault::DecisionEngine engine;
    auto result = engine.evaluate(cInput);
    
    return static_cast<NSInteger>(result);
}


@end
