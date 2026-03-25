//
//  FaceVaultVision.swift
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

import Vision
import CoreMedia
import CoreImage

public struct FaceLandmarks {
    public let boundingBox: CGRect
    public let landmarks: [CGPoint]
    public let yaw: Float
    public let pitch: Float
    public let roll: Float
    public let pixelBuffer: CVPixelBuffer?

}

public protocol FaceVaultVisionDelegate: AnyObject {
    func vision(_ vision: FaceVaultVision, didDetect landmarks: FaceLandmarks)
    func visionDidLoseFace(_ vision: FaceVaultVision)
    func visionDidDetectMultipleFaces(_ vision: FaceVaultVision, count: Int) // ← add this
}

// MARK: - FaceVaultVision
public class FaceVaultVision {
    public weak var delegate: FaceVaultVisionDelegate?
    private var lastFaceDetected = false
    private var currentPixelBuffer: CVPixelBuffer?

    public init() {}
    
    // MARK: - Process Frame

    public func process(pixelBuffer: CVPixelBuffer) {
        currentPixelBuffer = pixelBuffer
        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let self else { return }
            guard let results = request.results as? [VNFaceObservation] else { return }
            
            switch results.count {
            case 0:
                if self.lastFaceDetected {
                    self.lastFaceDetected = false
                    DispatchQueue.main.async { self.delegate?.visionDidLoseFace(self) }
                }
            case 1:
                self.lastFaceDetected = true
                self.process(face: results[0])
            default:
                self.lastFaceDetected = false
                DispatchQueue.main.async {
                    self.delegate?.visionDidDetectMultipleFaces(self, count: results.count)
                }
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        try? handler.perform([request])
    }
    
    // MARK: - Extract Landmarks
    private func process(face: VNFaceObservation) {
        
        guard let allPoints = face.landmarks?.allPoints else { return }

        // Head pose validation — reject if face not forward facing
        let yaw   = face.yaw?.floatValue ?? 0
        let pitch = face.pitch?.floatValue ?? 0
        let roll  = face.roll?.floatValue ?? 0
        
        // Head pose validation
        let maxAngle = Float(0.5)
        guard abs(yaw) < maxAngle && abs(pitch) < maxAngle && abs(roll) < maxAngle else {
            print("⚠️ FaceVault: Face angle rejected — yaw:\(yaw) pitch:\(pitch) roll:\(roll)")
            return
        }

        let points = allPoints.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        
        let landmarks = FaceLandmarks(
            boundingBox: face.boundingBox,
            landmarks:   points,
            yaw:         yaw,
            pitch:       pitch,
            roll:        roll,
            pixelBuffer: currentPixelBuffer  
        )
        
        DispatchQueue.main.async {
            self.delegate?.vision(self, didDetect: landmarks)
        }

        print("✅ Face detected — yaw:\(yaw) pitch:\(pitch) roll:\(roll) points:\(points.count)")
    }

}

