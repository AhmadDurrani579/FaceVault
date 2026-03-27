//
//  FaceVaultAgeEngine.hpp
//  FaceVault
//
//  Created by Ahmad on 26/03/2026.
//

#ifndef FaceVaultAgeEngine_hpp
#define FaceVaultAgeEngine_hpp

#ifdef __cplusplus
#include <vector>
#include <string>

namespace facevault {

struct AgeResult {
    float estimatedAge;   // e.g. 24.5
    float confidence;     // 0.0 - 1.0
    bool  isAdult;        // age >= ageThreshold
    int   ageThreshold;   // configurable default 18
    std::string ageRange; // e.g. "18-25"
    bool  success;
    std::string error;
};

class AgeEngine {
public:
    // Configurable threshold
    int ageThreshold = 18;

    // Evaluate raw age output from CoreML
    AgeResult evaluate(float rawAge) const;

    // Smooth multiple age estimates
    float smoothAge(const std::vector<float>& estimates) const;

    // Convert age to range string
    std::string ageRangeString(float age) const;

    // Calculate confidence based on distance from threshold
    float calculateConfidence(float age) const;
};

} // namespace facevault

#endif // __cplusplus
#endif // FaceVaultAgeEngine_hpp
