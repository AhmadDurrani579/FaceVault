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
        
        var copyBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            nil,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            nil,
            &copyBuffer
        )
        
        guard let safeCopy = copyBuffer else {
            isChecking = false
            return
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(safeCopy, CVPixelBufferLockFlags(rawValue: 0))
        if let src = CVPixelBufferGetBaseAddress(pixelBuffer),
           let dst = CVPixelBufferGetBaseAddress(safeCopy) {
            memcpy(dst, src, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(safeCopy, CVPixelBufferLockFlags(rawValue: 0))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            
            defer {
                DispatchQueue.main.async { self.isChecking = false }
            }
            
            self.vision.process(pixelBuffer: safeCopy, orientation: .up, maxAngle: 0.7)
            
            guard let landmarks = self.lastLandmarks else {
                self.consecutiveLostCount += 1
                DispatchQueue.main.async { self.isChecking = false }
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
                DispatchQueue.main.async {
                    self.delegate?.continuousAuth(self, didDetect: .faceLost)
                }
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
                if score >= self.matchThreshold {
                    self.delegate?.continuousAuth(self,
                        didDetect: .faceVerified(confidence: score))
                } else {
                    FaceVaultLogger.log("Continuous auth — different face detected", level: .warning)
                    self.delegate?.continuousAuth(self,
                        didDetect: .faceChanged(confidence: score))
                }
            }
        }
    }
}

// MARK: - Camera Delegate
extension FaceVaultContinuousAuth: FaceVaultCameraDelegate {
    public func camera(_ camera: FaceVaultCamera,
                       didOutput sampleBuffer: CMSampleBuffer) {
        guard isRunning, isChecking else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        checkFrame(pixelBuffer)
    }
}

// MARK: - Vision Delegate
extension FaceVaultContinuousAuth: FaceVaultVisionDelegate {
    public func vision(_ vision: FaceVaultVision, didDetect landmarks: FaceLandmarks) {
        lastLandmarks = landmarks
        DispatchQueue.main.async {
            self.delegate?.continuousAuth(self, didDetect: .faceVerified(confidence: 1.0))
        }
    }
    
    public func visionDidLoseFace(_ vision: FaceVaultVision) {
        lastLandmarks = nil
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
