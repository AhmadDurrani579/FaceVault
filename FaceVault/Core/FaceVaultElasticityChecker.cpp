//
//  FaceVaultElasticityChecker.cpp
//  FaceVault
//
//  Created by Ahmad on 08/05/2026.
//

#include "FaceVaultElasticityChecker.hpp"
#include <cmath>

namespace FaceVault {

float FaceVaultElasticityChecker::get(
    const std::map<std::string, float>& bs,
    const std::string& key) {
    auto it = bs.find(key);
    return it != bs.end() ? it->second : 0.0f;
}

ElasticityResult FaceVaultElasticityChecker::evaluate(
    const std::map<std::string, float>& blendShapes,
    ChallengeType challenge) {
    
    switch (challenge) {
        case ChallengeType::Blink:     return checkBlink(blendShapes);
        case ChallengeType::Smile:     return checkSmile(blendShapes);
        case ChallengeType::OpenMouth: return checkOpenMouth(blendShapes);
        case ChallengeType::TurnLeft:
        case ChallengeType::TurnRight: return checkTurn(blendShapes);
    }
}

ElasticityResult FaceVaultElasticityChecker::checkBlink(
    const std::map<std::string, float>& bs) {
    
    ElasticityResult result;
    result.passed = false;
    result.score = 0.0f;

    float blinkL = get(bs, "eyeBlink_L");
    float blinkR = get(bs, "eyeBlink_R");
    float lookDownL = get(bs, "eyeLookDown_L");
    float lookDownR = get(bs, "eyeLookDown_R");

    // Primary: both eyes must close
    if (blinkL < 0.7f || blinkR < 0.7f) {
        result.rejectReason = "Blink: eyes not closed enough";
        return result;
    }

    // Correlation: eyes must look down when closing
    // Real blink — eyeLookDown rises with eyeBlink
    // Photo/mask — eyeBlink fires but eyeLookDown stays low
    if (lookDownL < 0.25f || lookDownR < 0.25f) {
        result.rejectReason = "Blink: no correlated eye movement";
        return result;
    }

    // Score based on correlation strength
    float correlation = (lookDownL + lookDownR) /
                        (blinkL + blinkR);
    result.score = std::min(correlation * 2.0f, 1.0f);
    result.passed = true;
    
    printf("[FaceVault] Lock 2 Blink — blink:%.2f lookDown:%.2f score:%.2f\n",
           (blinkL + blinkR) / 2.0f,
           (lookDownL + lookDownR) / 2.0f,
           result.score);
    
    return result;
}

ElasticityResult FaceVaultElasticityChecker::checkSmile(
    const std::map<std::string, float>& bs) {

    ElasticityResult result;
    result.passed = false;
    result.score = 0.0f;

    float smileL = get(bs, "mouthSmile_L");
    float smileR = get(bs, "mouthSmile_R");
    float cheekL = get(bs, "cheekSquint_L");
    float cheekR = get(bs, "cheekSquint_R");
    float noseL  = get(bs, "noseSneer_L");
    float noseR  = get(bs, "noseSneer_R");

    // Primary: smile must be present
    if (smileL < 0.5f || smileR < 0.5f) {
        result.rejectReason = "Smile: mouth not smiling";
        return result;
    }

    // Correlation: cheeks must rise with smile
    // Real face — cheeks compress upward
    // Mask/photo — smile alone fires, cheeks don't move
    if (cheekL < 0.15f || cheekR < 0.15f) {
        result.rejectReason = "Smile: cheeks not rising";
        return result;
    }

    // Correlation: nose must widen
    if (noseL < 0.08f && noseR < 0.08f) {
        result.rejectReason = "Smile: no nose response";
        return result;
    }

    float cheekRatio = (cheekL + cheekR) / (smileL + smileR);
    result.score = std::min(cheekRatio * 1.5f, 1.0f);
    result.passed = true;
    
    printf("[FaceVault] Lock 2 Smile — smile:%.2f cheek:%.2f nose:%.2f score:%.2f\n",
           (smileL + smileR) / 2.0f,
           (cheekL + cheekR) / 2.0f,
           (noseL + noseR) / 2.0f,
           result.score);
    
    return result;
}

ElasticityResult FaceVaultElasticityChecker::checkOpenMouth(
    const std::map<std::string, float>& bs) {

    ElasticityResult result;
    result.passed = false;
    result.score = 0.0f;

    float jawOpen    = get(bs, "jawOpen");
    float browInner  = get(bs, "browInnerUp");
    float browOuterL = get(bs, "browOuterUp_L");
    float browOuterR = get(bs, "browOuterUp_R");
    float stretchL   = get(bs, "mouthStretch_L");
    float stretchR   = get(bs, "mouthStretch_R");

    // Primary: jaw must open
    if (jawOpen < 0.4f) {
        result.rejectReason = "OpenMouth: jaw not open enough";
        return result;
    }

    // Correlation: brows must rise involuntarily
    // Real face — opening mouth pulls facial muscles,
    // brows rise as a reflex
    // Mask/photo — jawOpen fires, brows stay neutral
    if (browInner < 0.15f) {
        result.rejectReason = "OpenMouth: no brow response";
        return result;
    }

    // Correlation: mouth must stretch
    if (stretchL < 0.2f || stretchR < 0.2f) {
        result.rejectReason = "OpenMouth: no stretch response";
        return result;
    }

    float browResponse = (browInner + browOuterL + browOuterR) / 3.0f;
    result.score = std::min(browResponse / jawOpen, 1.0f);
    result.passed = true;
    
    printf("[FaceVault] Lock 2 OpenMouth — jaw:%.2f brow:%.2f stretch:%.2f score:%.2f\n",
           jawOpen,
           browResponse,
           (stretchL + stretchR) / 2.0f,
           result.score);
    
    return result;
}

ElasticityResult FaceVaultElasticityChecker::checkTurn(
    const std::map<std::string, float>& bs) {

    ElasticityResult result;
    result.passed = true;
    result.score = 1.0f;
    // Turn is already validated by head yaw in ARKit
    // No additional elasticity check needed
    return result;
}

} // namespace FaceVault
