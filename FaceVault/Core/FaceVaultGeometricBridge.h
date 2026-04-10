//
//  FaceVaultGeometricBridge.h
//  FaceVault
//
//  Created by Ahmad on 10/04/2026.
//

#pragma once
#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface FaceVaultGeometricBridge : NSObject

- (BOOL)authenticateWithEnrolledMesh:(NSArray<NSValue *> *)enrolledMesh
                            liveMesh:(NSArray<NSValue *> *)liveMesh
                         depthValues:(NSArray<NSNumber *> *)depthValues
                   enrolledEmbedding:(NSArray<NSNumber *> *)enrolledEmbedding
                       liveEmbedding:(NSArray<NSNumber *> *)liveEmbedding
                         rejectReason:(NSString *_Nullable *_Nullable)rejectReason;

@end

NS_ASSUME_NONNULL_END
