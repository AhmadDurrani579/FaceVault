//
//  FaceVaultDecisionBridge.m
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

#import <Foundation/Foundation.h>
#import "FaceVaultDecisionBridge.h"
#include "FaceVaultDecision.hpp"
#include "FaceVaultIntegrity.hpp"

@implementation FaceVaultDecisionInput
@end

@implementation FaceVaultDecisionBridge

- (NSInteger)evaluate:(FaceVaultDecisionInput *)input {
    
    #if !DEBUG
    // Only run integrity checks in Release builds
    facevault::IntegrityChecker checker;
    facevault::IntegrityResult integrity = checker.check();
    
    if (!integrity.passed) {
        NSLog(@"❌ FaceVault: Integrity check failed — %s", integrity.reason.c_str());
        return 5;
    }
    #else
    printf("✅ FaceVault: Integrity checks skipped (DEBUG mode)\n");
    #endif
    
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
