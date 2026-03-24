//
//  FaceVaultMatcher.hpp
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

#ifndef FaceVaultMatcher_hpp
#define FaceVaultMatcher_hpp

#pragma once

#include <stdio.h>
#include <vector>
#include <cmath>

namespace facevault {
class Matcher {
    
public:
    // Compare two 128-dim face embedding vectors
    // Returns similarity score between 0.0 and 1.0
    static float cosineSimilarity(const std::vector<float> &a,
                                  const std::vector<float> &b);
    
    // Returns true if score is above threshold
    static bool isMatch(const std::vector<float> &a,
                        const std::vector<float> &b,
                        float threshold = 0.75f);
  
    
};
}// namespace facevault
#endif /* FaceVaultMatcher_hpp */
