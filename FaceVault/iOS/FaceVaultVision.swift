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
    
    public init() {}
    
    // MARK: - Process Frame

    public func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let self else { return }
            
            if let error {
                print("FaceVault Vision error: \(error)")
                return
            }
            
            guard let results = request.results as? [VNFaceObservation] else { return }
            
            switch results.count {
            case 0:
                if self.lastFaceDetected {
                    self.lastFaceDetected = false
                    DispatchQueue.main.async {
                        self.delegate?.visionDidLoseFace(self)
                    }
                }
            case 1:
                self.lastFaceDetected = true
                self.process(face: results[0])
            default:
                self.lastFaceDetected = false
                DispatchQueue.main.async {
                    self.delegate?.visionDidDetectMultipleFaces(self, count: results.count)
                }
                print("FaceVault: \(results.count) faces detected — rejected for security")
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                             orientation: .up,
                                             options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("FaceVault Vision handler error: \(error)")
        }
    }
    
    // MARK: - Extract Landmarks
    private func process(face: VNFaceObservation) {
        guard let allPoints = face.landmarks?.allPoints else { return }
        
        // Extract all 76 landmark points
        let points = allPoints.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        
        // Head pose angles
        let yaw   = face.yaw?.floatValue ?? 0
        let pitch = face.pitch?.floatValue ?? 0
        let roll  = face.roll?.floatValue ?? 0
        
        let landmarks = FaceLandmarks(
            boundingBox: face.boundingBox,
            landmarks: points,
            yaw: yaw,
            pitch: pitch,
            roll: roll
        )
        
        DispatchQueue.main.async {
            self.delegate?.vision(self, didDetect: landmarks)
        }
        
        print("✅ Face detected — yaw: \(yaw) pitch: \(pitch) roll: \(roll) points: \(points.count)")
    }

}

