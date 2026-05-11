//
//  FaceVaultElasticityChecker.hpp
//  FaceVault
//
//  Created by Ahmad on 08/05/2026.
//

// FaceVaultElasticityChecker.hpp
#pragma once
#include <map>
#include <string>

namespace FaceVault {

enum class ChallengeType {
    Blink,
    Smile,
    OpenMouth,
    TurnLeft,
    TurnRight
};

struct ElasticityResult {
    bool passed;
    float score;        // 0.0 - 1.0
    std::string rejectReason;
};

class FaceVaultElasticityChecker {
public:
    ElasticityResult evaluate(
        const std::map<std::string, float>& blendShapes,
        ChallengeType challenge
    );

private:
    ElasticityResult checkBlink(const std::map<std::string, float>&);
    ElasticityResult checkSmile(const std::map<std::string, float>&);
    ElasticityResult checkOpenMouth(const std::map<std::string, float>&);
    ElasticityResult checkTurn(const std::map<std::string, float>&);
    
    float get(const std::map<std::string, float>& bs,
              const std::string& key);
};

} // namespace FaceVault
