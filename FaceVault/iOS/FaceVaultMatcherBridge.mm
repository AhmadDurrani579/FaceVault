//
//  FaceVaultMatcherBridge.mm
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

#import <Foundation/Foundation.h>
#import "FaceVaultMatcherBridge.h"
#include "FaceVaultMatcher.hpp"

@implementation FaceVaultMatcherBridge

-(float)cosineSimilarity:(NSArray<NSNumber *> *)a b:(NSArray<NSNumber *> *)b {
    std::vector<float> vecA, vecB;
    for (NSNumber *n in a) vecA.push_back(n.floatValue);
    for (NSNumber *n in b) vecB.push_back(n.floatValue) ;
    return facevault::Matcher::cosineSimilarity(vecA, vecB);
}

- (BOOL)isMatch:(NSArray<NSNumber *> *)a b:(NSArray<NSNumber *> *)b threshold:(float)threshold {
    std::vector<float> vecA, vecB;
    for (NSNumber *n in a) vecA.push_back(n.floatValue);
    for (NSNumber *n in b) vecB.push_back(n.floatValue);
    return facevault::Matcher::isMatch(vecA, vecB);
}

- (float)matchWithAveraging:(NSArray<NSArray<NSNumber *> *> *)liveEmbeddings stored:(NSArray<NSNumber *> *)stored {
    
    std::vector<float> storedVec;
    for(NSNumber *n in stored) storedVec.push_back(n.floatValue);
    
    // Convert live embeddings
    std::vector<std::vector<float>> liveVecs;
    for (NSArray<NSNumber *> *emb in liveEmbeddings) {
        std::vector<float> vec;
        for (NSNumber *n in emb) vec.push_back(n.floatValue);
        liveVecs.push_back(vec);
    }
    return facevault::Matcher::matchWithAveraging(liveVecs, storedVec);
}

- (NSArray<NSNumber *> *)averageEmbeddings:(NSArray<NSArray<NSNumber *> *> *)embeddings {
    std::vector<std::vector<float>> vecs;
    for (NSArray<NSNumber *> *emb in embeddings) {
        std::vector<float> vec;
        for (NSNumber *n in emb) vec.push_back(n.floatValue);
        vecs.push_back(vec);
    }
    auto avg = facevault::Matcher::averageEmbeddings(vecs);
    NSMutableArray *result = [NSMutableArray array];
    for (float v : avg) [result addObject:@(v)];
    return result;
}

@end
