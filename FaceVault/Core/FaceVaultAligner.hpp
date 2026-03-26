//
//  FaceVaultAligner.hpp
//  FaceVault
//
//  Created by Ahmad on 26/03/2026.
//

#ifndef FaceVaultAligner_hpp
#define FaceVaultAligner_hpp
#ifdef __cplusplus
#include <vector>
#include <string>
#include <cstdint>
#include "FaceVaultPreprocessor.hpp"

namespace facevault {
struct AlignResult {
    ImageBuffer alignedFace;
    float       rollAngle;
    bool        success;
    std::string error;
    
};
class FaceAligner{
public:
    // Main entry — align face using eye positions

    AlignResult align(const ImageBuffer& croppedFace,
                      float leftEyeX,  float leftEyeY,
                      float rightEyeX, float rightEyeY) const;
    
private:
    // ArcFace standard eye positions in 112x112
    const float targetLeftEyeX = 38.29f;
    const float targetLeftEyeY  = 51.69f;
    const float targetRightEyeX = 73.53f;
    const float targetRightEyeY = 51.50f;
    const int   targetSize      = 112;

};
} // namespace facevault

#endif // __cplusplus
#endif // FaceVaultAligner_hpp
