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

@end
