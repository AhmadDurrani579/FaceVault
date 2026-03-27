//
//  FaceVaultAgeEngine.cpp
//  FaceVault
//
//  Created by Ahmad on 26/03/2026.
//

#include "FaceVaultAgeEngine.hpp"
#include <cmath>
#include <numeric>
#include <algorithm>

namespace facevault {

// MARK: - Evaluate
AgeResult AgeEngine::evaluate(float rawAge) const {
    AgeResult result;
    result.success      = false;
    result.ageThreshold = ageThreshold;

    if (rawAge < 0 || rawAge > 120) {
        result.error = "Invalid age estimate";
        return result;
    }

    result.estimatedAge = rawAge;
    result.isAdult      = rawAge >= static_cast<float>(ageThreshold);
    result.ageRange     = ageRangeString(rawAge);
    result.confidence   = calculateConfidence(rawAge);
    result.success      = true;

    printf("✅ FaceVault C++: Age — %.1f years | range: %s | adult: %s | confidence: %.2f\n",
           rawAge,
           result.ageRange.c_str(),
           result.isAdult ? "yes" : "no",
           result.confidence);

    return result;
}

// MARK: - Smooth
float AgeEngine::smoothAge(const std::vector<float>& estimates) const {
    if (estimates.empty()) return 0.0f;

    // Remove outliers — trim min and max if enough samples
    std::vector<float> sorted = estimates;
    std::sort(sorted.begin(), sorted.end());

    int start = 0;
    int end   = static_cast<int>(sorted.size());

    if (sorted.size() >= 5) {
        start = 1; // remove lowest
        end   = static_cast<int>(sorted.size()) - 1; // remove highest
    }

    float sum = 0.0f;
    for (int i = start; i < end; i++) sum += sorted[i];
    return sum / (end - start);
}

// MARK: - Age Range
std::string AgeEngine::ageRangeString(float age) const {
    if (age < 13)  return "0-12";
    if (age < 18)  return "13-17";
    if (age < 25)  return "18-24";
    if (age < 35)  return "25-34";
    if (age < 45)  return "35-44";
    if (age < 55)  return "45-54";
    if (age < 65)  return "55-64";
    return "65+";
}

// MARK: - Confidence
float AgeEngine::calculateConfidence(float age) const {
    float threshold = static_cast<float>(ageThreshold);
    float distance  = std::abs(age - threshold);

    // Close to threshold = low confidence
    // Far from threshold = high confidence
    // Within 2 years = low confidence (0.3)
    // 5+ years away  = high confidence (0.95)

    if (distance < 2.0f) return 0.3f;
    if (distance < 4.0f) return 0.6f;
    if (distance < 6.0f) return 0.8f;
    return 0.95f;
}

} // namespace facevault
