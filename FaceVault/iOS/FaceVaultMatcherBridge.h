//
//  FaceVaultMatcherBridge.h
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

#ifndef FaceVaultMatcherBridge_h
#define FaceVaultMatcherBridge_h

#import <Foundation/Foundation.h>

@interface FaceVaultMatcherBridge : NSObject

-(float)cosineSimilarity:(NSArray<NSNumber *> *)a
                       b:(NSArray<NSNumber *> *)b;
- (BOOL)isMatch:(NSArray<NSNumber *> *)a
              b:(NSArray<NSNumber *> *)b
      threshold:(float)threshold;

// Average multiple embeddings and compare ← NEW
- (float)matchWithAveraging:(NSArray<NSArray<NSNumber *> *> *)liveEmbeddings
                     stored:(NSArray<NSNumber *> *)stored;

// Average embeddings ← NEW
- (NSArray<NSNumber *> *)averageEmbeddings:(NSArray<NSArray<NSNumber *> *> *)embeddings;


@end

#endif /* FaceVaultMatcherBridge_h */
