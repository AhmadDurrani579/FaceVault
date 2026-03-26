//
//  FaceVaultAligner.cpp
//  FaceVault
//
//  Created by Ahmad on 26/03/2026.
//

#include "FaceVaultAligner.hpp"
#include <opencv2/opencv.hpp>
#include <cmath>

namespace facevault{

AlignResult FaceAligner::align(const ImageBuffer &croppedFace,
                               float leftEyeX, float leftEyeY,
                               float rightEyeX, float rightEyeY) const {
        
        AlignResult result;
        result.success = false;
        if (croppedFace.data.empty()) {
            result.error = "Empty Input";
            return result;
        }
        cv::Mat img;
        if (croppedFace.channels == 4){
            cv::Mat bgra(croppedFace.height, croppedFace.width, CV_8UC4,
                         const_cast<uint8_t*>(croppedFace.data.data()));
            cv::cvtColor(bgra, img, cv::COLOR_BGRA2BGR);
        }else {
            img = cv::Mat(croppedFace.height, croppedFace.width,
                          CV_8UC3,
                          const_cast<uint8_t*>(croppedFace.data.data())).clone();
        }
        
        // Step 1 — convert normalized eye coords to pixel coords
        float srcLeftX  = leftEyeX  * croppedFace.width;
        float srcLeftY  = leftEyeY  * croppedFace.height;
        float srcRightX = rightEyeX * croppedFace.width;
        float srcRightY = rightEyeY * croppedFace.height;

        printf("👁 Eyes — left:(%.1f,%.1f) right:(%.1f,%.1f)\n",
               srcLeftX, srcLeftY, srcRightX, srcRightY);

        // Step 2 — calculate rotation angle
        float dx = srcRightX - srcLeftX;
        float dy = srcRightY - srcLeftY;
        float angle = std::atan2(dy, dx) * 180.0f / M_PI;

        result.rollAngle = angle;
        printf("🔄 Alignment angle: %.2f degrees\n", angle);

        // Step 3 — calculate scale
        float srcDist = std::sqrt(dx * dx + dy * dy);
        float dstDist = std::sqrt(
            std::pow(targetRightEyeX - targetLeftEyeX, 2) +
            std::pow(targetRightEyeY - targetLeftEyeY, 2)
        );
        float scale = dstDist / srcDist;

        // Step 4 — calculate center between eyes
        float eyeCenterX = (srcLeftX + srcRightX) / 2.0f;
        float eyeCenterY = (srcLeftY + srcRightY) / 2.0f;

        // Step 5 — get rotation matrix
        cv::Point2f center(eyeCenterX, eyeCenterY);
        cv::Mat rotMat = cv::getRotationMatrix2D(center, angle, scale);

        // Step 6 — adjust translation to target eye center
        float targetCenterX = (targetLeftEyeX + targetRightEyeX) / 2.0f;
        float targetCenterY = (targetLeftEyeY + targetRightEyeY) / 2.0f;
        rotMat.at<double>(0, 2) += targetCenterX - eyeCenterX;
        rotMat.at<double>(1, 2) += targetCenterY - eyeCenterY;

        // Step 7 — apply transformation
        cv::Mat aligned;
        cv::warpAffine(img, aligned, rotMat,
                       cv::Size(targetSize, targetSize),
                       cv::INTER_LINEAR,
                       cv::BORDER_REFLECT);

        printf("✅ FaceVault C++: Face aligned — angle:%.2f scale:%.2f\n",
               angle, scale);

        // Convert back to ImageBuffer
        ImageBuffer output;
        output.width    = aligned.cols;
        output.height   = aligned.rows;
        output.channels = 3;
        output.data.assign(aligned.data,
                           aligned.data + aligned.total() * aligned.channels());
        result.alignedFace = output;
        result.success     = true;
        return result;
    }
    
}
