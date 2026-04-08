//
//  FaceVaultContinuousAuth.swift
//  FaceVault
//
//  Created by Ahmad on 26/03/2026.
//

import AVFoundation
import Vision
import CoreMedia

public enum ContinuousAuthEvent {
    case faceVerified(confidence: Float)
    case faceLost
    case faceChanged(confidence: Float)
    case multipleFaces
}

public protocol FaceVaultContinuousAuthDelegate: AnyObject {
    func continuousAuth(_ auth: FaceVaultContinuousAuth,
                        didDetect event: ContinuousAuthEvent)
}

public class FaceVaultContinuousAuth: NSObject {
    
    private let camera        = FaceVaultCamera()
    private let vision        = FaceVaultVision()
    private let embedder      = FaceVaultEmbedder()
    private let bridge        = FaceVaultMatcherBridge()
    private let preprocessor  = FaceVaultPreprocessorBridge()
    private var consecutiveGoodFrames = 0
    private var lastVisionTime: Date = .distantPast

    public weak var delegate: FaceVaultContinuousAuthDelegate?
    public var onStopped: (() -> Void)?
    
    private var storedEmbedding: [Float]?
    private var checkInterval: TimeInterval = 5.0
    private var matchThreshold: Float = 0.75
    private var timer: Timer?
    private var isRunning = false
    private var lastLandmarks: FaceLandmarks?
    private var isChecking = false
    private var consecutiveLostCount = 0

    public override init() {
        super.init()
        vision.delegate = self
        camera.delegate = self
    }
    
    // MARK: - Public API
    public func start(storedEmbedding: [Float],
                      interval: TimeInterval = 5.0,
                      threshold: Float = 0.75,
                      maxDuration: TimeInterval) {
        self.storedEmbedding = storedEmbedding
        self.checkInterval   = interval
        self.matchThreshold  = threshold
        self.isRunning       = true
        
        FaceVaultLogger.log("Continuous auth started — interval:\(Int(interval))s duration:\(Int(maxDuration))s")
        
        camera.start()
        
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(
                timeInterval: interval,
                target: self,
                selector: #selector(self.performCheck),
                userInfo: nil,
                repeats: true
            )
            
            DispatchQueue.main.asyncAfter(deadline: .now() + maxDuration) {
                [weak self] in
                guard let self, self.isRunning else { return }
                FaceVaultLogger.log("Continuous auth session ended — timeout")
                self.stop()
            }
        }
    }
    
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        camera.stop()
        FaceVaultLogger.log("Continuous auth stopped")
        DispatchQueue.main.async {
            self.onStopped?()
        }
    }

    // MARK: - Check
    @objc private func performCheck() {
        guard isRunning, !isChecking else { return }
        isChecking = true
    }
    
    private func checkFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRunning, isChecking else { return }
        guard let stored = storedEmbedding else { return }
        
        guard let safeCopy = copyPixelBuffer(pixelBuffer) else {
            isChecking = false
            return
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            
            defer {
                DispatchQueue.main.async { self.isChecking = false }
            }
            
            // Don't process Vision here — camera delegate handles it
            // Just use existing landmarks
            guard let landmarks = self.lastLandmarks else {
                self.consecutiveLostCount += 1
                return
            }
            
            self.consecutiveLostCount = 0
            
            let faceRect = FaceVaultFaceRect()
            faceRect.x             = Float(landmarks.boundingBox.origin.x)
            faceRect.y             = Float(landmarks.boundingBox.origin.y)
            faceRect.width         = Float(landmarks.boundingBox.size.width)
            faceRect.height        = Float(landmarks.boundingBox.size.height)
            faceRect.yaw           = landmarks.yaw
            faceRect.pitch         = landmarks.pitch
            faceRect.roll          = landmarks.roll
            faceRect.landmarkCount = Int32(landmarks.landmarks.count)
            faceRect.leftEyeX      = Float(landmarks.leftEye.x)
            faceRect.leftEyeY      = Float(landmarks.leftEye.y)
            faceRect.rightEyeX     = Float(landmarks.rightEye.x)
            faceRect.rightEyeY     = Float(landmarks.rightEye.y)
            
            guard let result = self.preprocessor.process(safeCopy, faceRect: faceRect),
                  result.success,
                  let processedBuffer = result.processedBuffer else {
                return
            }
            
            guard let embedding = self.embedder.generateEmbedding(from: processedBuffer) else {
                return
            }
            
            let nsA = embedding.map { NSNumber(value: $0) }
            let nsB = stored.map { NSNumber(value: $0) }
            let score = self.bridge.cosineSimilarity(nsA, b: nsB)
            
            FaceVaultLogger.log("Continuous check — score: \(String(format: "%.2f", score))")
            
            DispatchQueue.main.async {
                guard self.lastLandmarks != nil else { return }
                
                if score >= self.matchThreshold {
                    self.delegate?.continuousAuth(self,
                        didDetect: .faceVerified(confidence: score))
                } else {
                    FaceVaultLogger.log("Different face detected", level: .warning)
                    self.delegate?.continuousAuth(self,
                        didDetect: .faceChanged(confidence: score))
                }
            }
        }
    }

    private func copyPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        var copy: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            attrs,
            &copy
        )
        
        guard let dst = copy else { return nil }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(dst, CVPixelBufferLockFlags(rawValue: 0))
        
        if let src = CVPixelBufferGetBaseAddress(pixelBuffer),
           let dstAddr = CVPixelBufferGetBaseAddress(dst) {
            memcpy(dstAddr, src, CVPixelBufferGetDataSize(pixelBuffer))
        }
        
        CVPixelBufferUnlockBaseAddress(dst, CVPixelBufferLockFlags(rawValue: 0))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        return dst
    }

}

// MARK: - Camera Delegate
extension FaceVaultContinuousAuth: FaceVaultCameraDelegate {
    public func camera(_ camera: FaceVaultCamera,
                       didOutput sampleBuffer: CMSampleBuffer) {
        guard isRunning else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Vision throttle — every 0.3 seconds
        let now = Date()
        guard now.timeIntervalSince(lastVisionTime) > 0.3 else { return }
        lastVisionTime = now
        
        // Vision runs for blur/unblur
        vision.process(pixelBuffer: pixelBuffer, orientation: .up, maxAngle: 0.7)
        
        // Identity check only when timer fires
        guard isChecking else { return }
        checkFrame(pixelBuffer)
    }

}

// MARK: - Vision Delegate
extension FaceVaultContinuousAuth: FaceVaultVisionDelegate {
    public func vision(_ vision: FaceVaultVision,
                       didDetect landmarks: FaceLandmarks) {
        lastLandmarks = landmarks
        
        guard abs(landmarks.yaw) < 0.5 &&
              abs(landmarks.pitch) < 0.5 &&
              landmarks.landmarks.count > 30 else {
            consecutiveGoodFrames = 0
            return
        }
        
        consecutiveGoodFrames += 1
        
        // Only unblur after 3 consecutive good frames
        // Prevents false positives
        guard consecutiveGoodFrames >= 3 else { return }
        
        DispatchQueue.main.async {
            self.delegate?.continuousAuth(self,
                didDetect: .faceVerified(confidence: 1.0))
        }
    }

    public func visionDidLoseFace(_ vision: FaceVaultVision) {
        lastLandmarks = nil
        consecutiveGoodFrames = 0  // ← reset
        FaceVaultLogger.log("Continuous auth — face lost", level: .warning)
        DispatchQueue.main.async {
            self.delegate?.continuousAuth(self, didDetect: .faceLost)
        }
    }

    public func visionDidDetectMultipleFaces(_ vision: FaceVaultVision, count: Int) {
        FaceVaultLogger.log("Continuous auth — multiple faces detected", level: .warning)
        DispatchQueue.main.async {
            self.delegate?.continuousAuth(self, didDetect: .multipleFaces)
        }
    }
}
