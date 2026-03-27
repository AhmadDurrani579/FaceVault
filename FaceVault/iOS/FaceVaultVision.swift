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
    public let leftEye:     CGPoint
    public let rightEye:    CGPoint
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

    public func process(pixelBuffer: CVPixelBuffer,
                        orientation: CGImagePropertyOrientation = .leftMirrored,
                        maxAngle: Float = 0.5) {
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
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try? handler.perform([request])
    }
    
    // MARK: - Extract Landmarks
    private func process(face: VNFaceObservation) {
        guard let allPoints = face.landmarks?.allPoints else { return }
        
        let yaw   = face.yaw?.floatValue   ?? 0
        let pitch = face.pitch?.floatValue ?? 0
        let roll  = face.roll?.floatValue  ?? 0

        print("📐 Face angles — yaw:\(yaw) pitch:\(pitch) roll:\(roll)")

        let maxAngle = Float(0.5)
        guard abs(yaw) < maxAngle &&
              abs(pitch) < maxAngle &&
              abs(roll) < maxAngle else {
            print("⚠️ FaceVault: Face angle rejected")
            return
        }

        let points = allPoints.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        
        // Extract eye centers from landmarks
        var leftEye  = CGPoint(x: 0.35, y: 0.4)  // defaults
        var rightEye = CGPoint(x: 0.65, y: 0.4)
        
        if let leftEyeRegion = face.landmarks?.leftEye {
            let pts = leftEyeRegion.normalizedPoints
            let avgX = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
            let avgY = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
            leftEye = CGPoint(x: avgX, y: avgY)
        }
        
        if let rightEyeRegion = face.landmarks?.rightEye {
            let pts = rightEyeRegion.normalizedPoints
            let avgX = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
            let avgY = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
            rightEye = CGPoint(x: avgX, y: avgY)
        }
        
        let landmarks = FaceLandmarks(
            boundingBox: face.boundingBox,
            landmarks:   points,
            yaw:         yaw,
            pitch:       pitch,
            roll:        roll,
            pixelBuffer: currentPixelBuffer,
            leftEye:     leftEye,
            rightEye:    rightEye
        )
        
        DispatchQueue.main.async {
            self.delegate?.vision(self, didDetect: landmarks)
        }
    }
    
    public func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let self else { return }
            
            if let error {
                print("❌ FaceVault Vision error: \(error)")
                return
            }
            
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
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                             orientation: .up,
                                             options: [:])
        try? handler.perform([request])
    }

}

