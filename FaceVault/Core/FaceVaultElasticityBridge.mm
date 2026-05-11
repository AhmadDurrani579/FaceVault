//
//  FaceVaultElasticityBridge.m
//  FaceVault
//
//  Created by Ahmad on 08/05/2026.
//


#import "FaceVaultElasticityBridge.h"
#import "FaceVaultElasticityChecker.hpp"

@implementation FaceVaultElasticityResult
@end

@implementation FaceVaultElasticityBridge

- (FaceVaultElasticityResult *)evaluate:(NSDictionary<NSString *, NSNumber *> *)blendShapes
                              challenge:(FaceVaultChallengeType)challenge {
    
    // Convert NSDictionary to std::map
    std::map<std::string, float> bs;
    for (NSString *key in blendShapes) {
        bs[key.UTF8String] = blendShapes[key].floatValue;
    }
    
    // Convert challenge type
    FaceVault::ChallengeType cType;
    switch (challenge) {
        case FaceVaultChallengeTypeBlink:
            cType = FaceVault::ChallengeType::Blink; break;
        case FaceVaultChallengeTypeSmile:
            cType = FaceVault::ChallengeType::Smile; break;
        case FaceVaultChallengeTypeOpenMouth:
            cType = FaceVault::ChallengeType::OpenMouth; break;
        case FaceVaultChallengeTypeTurnLeft:
            cType = FaceVault::ChallengeType::TurnLeft; break;
        case FaceVaultChallengeTypeTurnRight:
            cType = FaceVault::ChallengeType::TurnRight; break;
    }
    
    FaceVault::FaceVaultElasticityChecker checker;
    FaceVault::ElasticityResult result = checker.evaluate(bs, cType);
    
    FaceVaultElasticityResult *objcResult = [[FaceVaultElasticityResult alloc] init];
    objcResult.passed = result.passed;
    objcResult.score = result.score;
    objcResult.rejectReason = [NSString stringWithUTF8String:result.rejectReason.c_str()];
    
    return objcResult;
}

@end
