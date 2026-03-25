//
//  FaceVaultDecisionBridge.h
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

#ifndef FaceVaultDecisionBridge_h
#define FaceVaultDecisionBridge_h

#import <Foundation/Foundation.h>

@interface FaceVaultDecisionInput : NSObject
@property (nonatomic) float embeddingScore;
@property (nonatomic) float livenessScore;
@property (nonatomic) BOOL  challengePassed;
@property (nonatomic) BOOL  singleFaceDetected;
@property (nonatomic) int   landmarkCount;
@end

@interface FaceVaultDecisionBridge : NSObject
- (NSInteger)evaluate:(FaceVaultDecisionInput *)input;
@end

#endif /* FaceVaultDecisionBridge_h */
