//
//  FaceVaultElasticityBridge.h
//  FaceVault
//
//  Created by Ahmad on 08/05/2026.
//

#import <Foundation/Foundation.h>

@interface FaceVaultElasticityResult : NSObject
@property (nonatomic) BOOL passed;
@property (nonatomic) float score;
@property (nonatomic, strong) NSString *rejectReason;
@end

typedef NS_ENUM(NSInteger, FaceVaultChallengeType) {
    FaceVaultChallengeTypeBlink,
    FaceVaultChallengeTypeSmile,
    FaceVaultChallengeTypeOpenMouth,
    FaceVaultChallengeTypeTurnLeft,
    FaceVaultChallengeTypeTurnRight
};

@interface FaceVaultElasticityBridge : NSObject
- (FaceVaultElasticityResult *)evaluate:(NSDictionary<NSString *, NSNumber *> *)blendShapes
                              challenge:(FaceVaultChallengeType)challenge;

@end

