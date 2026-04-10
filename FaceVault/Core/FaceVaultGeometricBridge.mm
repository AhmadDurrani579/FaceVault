//
//  FaceVaultGeometricBridge.m
//  FaceVault
//
//  Created by Ahmad on 10/04/2026.
//

#import <Foundation/Foundation.h>
#import "FaceVaultGeometricBridge.h"
#import "FaceVaultGeometricMatcher.hpp"

@implementation FaceVaultGeometricBridge

- (BOOL)authenticateWithEnrolledMesh:(NSArray<NSValue *> *)enrolledMesh
                            liveMesh:(NSArray<NSValue *> *)liveMesh
                         depthValues:(NSArray<NSNumber *> *)depthValues
                   enrolledEmbedding:(NSArray<NSNumber *> *)enrolledEmbedding
                       liveEmbedding:(NSArray<NSNumber *> *)liveEmbedding
                         rejectReason:(NSString *_Nullable *_Nullable)rejectReason
{
    // Convert enrolled mesh
    std::vector<simd_float3> enrolled;
    for (NSValue *v in enrolledMesh) {
        simd_float3 p;
        [v getValue:&p];
        enrolled.push_back(p);
    }

    // Convert live mesh
    std::vector<simd_float3> live;
    for (NSValue *v in liveMesh) {
        simd_float3 p;
        [v getValue:&p];
        live.push_back(p);
    }

    // Convert depth values
    std::vector<float> depth;
    for (NSNumber *n in depthValues) {
        depth.push_back(n.floatValue);
    }

    // Convert enrolled embedding
    std::vector<float> enrolledEmb;
    for (NSNumber *n in enrolledEmbedding) {
        enrolledEmb.push_back(n.floatValue);
    }

    // Convert live embedding
    std::vector<float> liveEmb;
    for (NSNumber *n in liveEmbedding) {
        liveEmb.push_back(n.floatValue);
    }

    // Call C++ decision engine
    facevault::GeometricMatcher matcher;
    printf("Bridge — enrolledEmb size: %zu first: %f\n", enrolledEmb.size(), enrolledEmb.empty() ? 0 : enrolledEmb[0]);
    printf("Bridge — liveEmb size: %zu first: %f\n", liveEmb.size(), liveEmb.empty() ? 0 : liveEmb[0]);

    facevault::AuthResult result = matcher.decide(
        enrolled,
        live,
        depth,
        enrolledEmb,
        liveEmb
    );

    // Pass reject reason back to Swift
    if (rejectReason && !result.authenticated) {
        *rejectReason = [NSString stringWithUTF8String:result.rejectReason.c_str()];
    }

    printf("FaceVault: Geometric=%.4f Depth=%.4f Embedding=%.4f\n",
           result.geometricScore,
           result.depthVariance,
           result.embeddingScore);

    return result.authenticated ? YES : NO;
}

@end
