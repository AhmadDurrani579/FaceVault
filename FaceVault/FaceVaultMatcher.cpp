//
//  FaceVaultMatcher.cpp
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

#include "FaceVaultMatcher.hpp"
#include <stdexcept>

namespace facevault {
    float Matcher::cosineSimilarity(const std::vector<float>& a,
                                     const std::vector<float>& b) {
        if (a.size() != b.size()) throw std::invalid_argument("Vector size mismatch");

        float dot = 0.0f, normA = 0.0f, normB = 0.0f;
        for (size_t i = 0; i < a.size(); i++) {
            dot   += a[i] * b[i];
            normA += a[i] * a[i];
            normB += b[i] * b[i];
        }
        return dot / (std::sqrt(normA) * std::sqrt(normB));
    }

    bool Matcher::isMatch(const std::vector<float>& a,
                          const std::vector<float>& b,
                          float threshold) {
        return cosineSimilarity(a, b) >= threshold;
    }
}
