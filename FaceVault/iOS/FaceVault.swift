//
//  FaceVaultSDK.swift
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//


import Foundation
import ARKit
import CoreMedia

// MARK: - Public Result
public enum FaceVaultResult {
    case authenticated(confidence: Float)
    case deniedNoMatch
    case deniedLiveness
    case deniedMultipleFaces
    case deniedInsufficientData
    case deniedTampered
    case requiresRetry
}

// MARK: - FaceVaultSDK
public class FaceVaultSDK: NSObject {
    
    // MARK: - Components
    private let camera    = FaceVaultCamera()
    private let vision    = FaceVaultVision()
    private let embedder  = FaceVaultEmbedder()
    private let liveness  = FaceVaultLiveness()
    private let bridge    = FaceVaultMatcherBridge()
    private let storage   = FaceVaultStorage()
    private let segmentorML = FaceVaultSegmentorML()
    private let ageEstimator = FaceVaultAgeEngine()
    private lazy var continuousAuth = FaceVaultContinuousAuth()
    private var lastIRLandmarks: FaceVaultIRLandmarks?

    // MARK: - State
    private var onResult: ((FaceVaultResult) -> Void)?
    private var enrollCompletion: ((Bool) -> Void)?
    private var currentEmbedding: [Float]?
    private var storedEmbedding: [Float]?
    private var landmarkCount: Int = 0
    private var livenessScore: Float = 0
    private var challengePassed: Bool = false
    private var singleFaceDetected: Bool = false
    private weak var previewView: FaceVaultPreviewView?
    private var lastEmbeddingTime: Date = .distantPast
    private var isEnrolling = false
    private var enrollCompleted = false
    private let preprocessor = FaceVaultPreprocessorBridge()
    private var lastLandmarks: FaceLandmarks?
    private var enrollEmbeddings: [[Float]] = []
    private let maxEnrollFrames = 10
    private var liveEmbeddings: [[Float]] = []
    private let maxLiveFrames = 5
    private var lastSegmentTime: Date = .distantPast
    private static var continuousAuthHandlerKey: UInt8 = 0
    private var lastPixelBuffer: CVPixelBuffer?
    
    private var capturedZones: Set<String> = []
    private let totalZones = 5

    public var onContinuousAuthStopped: (() -> Void)? {
        didSet {
            continuousAuth.onStopped = onContinuousAuthStopped
        }
    }

    // MARK: - Init
    public override init() {
        super.init()
        vision.delegate   = self
        liveness.delegate = self
        storage.clearOnFreshInstall()
        FaceVaultLogger.log("FaceVault SDK initialized")

//        warmUp()
    }
    
    private func warmUp() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 112, 112, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            if let buffer = pixelBuffer {
                _ = self.embedder.generateEmbedding(from: buffer)
                _ = self.segmentorML.generateMask(from: buffer)
            }
        }
    }
    
    private func attachCameraPreview() {
        previewView?.attachCameraSession(camera.captureSession)
    }
    
    public func prepare(completion: @escaping () -> Void) {
        FaceVaultLogger.log("Preparing SDK — warming up models...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 112, 112, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            
            if let buffer = pixelBuffer {
                _ = self.embedder.generateEmbedding(from: buffer)
            }
            FaceVaultLogger.log("SDK ready")

            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    public func isEnrolled() -> Bool {
        let enrolled = storage.hasEnrolledFace()
        FaceVaultLogger.log("Enrollment status: \(enrolled ? "enrolled" : "not enrolled")")
        return enrolled
    }
    
    public func logout() {
        _ = storage.deleteEmbedding()
        storedEmbedding = nil
        stop()
        stopContinuousAuth()
        FaceVaultLogger.log("Logged out — embedding deleted")

    }


    // MARK: - Public API
    public func enroll(completion: @escaping (Bool) -> Void) {
        #if targetEnvironment(simulator)
        completion(false)
        return
        #endif
        
        FaceVaultLogger.log("Enrollment started")

        print("🔵 enroll() called — isEnrolling = \(isEnrolling)")
        isEnrolling = true
        print("🔵 isEnrolling set to true")
        enrollCompleted = false
        enrollCompletion = completion
        currentEmbedding = nil
        enrollEmbeddings = []
        capturedZones = []          // ← reset zones
        
        previewView?.resetProgress() // ← reset progress ring
        previewView?.showMessage("Position your face in the oval")
        
        // Start ARKit IMMEDIATELY
        liveness.startEnrollMode()
        attachLivenessPreview()
        
        // Face ID in background — no 8 second timer
        // Zones control when enroll finishes
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            _ = self.storage.deleteEmbedding()
        }
    }
    
    private func updateEnrollProgress(yaw: Float, pitch: Float) {
        guard isEnrolling else { return }
        
        var zone = ""
        
        if abs(yaw) < 0.1 && abs(pitch) < 0.1 {
            zone = "center"
        } else if yaw < -0.2 {  // ← stricter threshold
            zone = "left"
        } else if yaw > 0.2 {
            zone = "right"
        } else if pitch > 0.2 {
            zone = "up"
        } else if pitch < -0.2 {
            zone = "down"
        }
        
        guard !zone.isEmpty, !capturedZones.contains(zone) else { return }
        
        // Delay between zone captures — feels more deliberate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.isEnrolling else { return }
            guard !self.capturedZones.contains(zone) else { return }
            
            self.capturedZones.insert(zone)
            let progress = Float(self.capturedZones.count) / Float(self.totalZones)
            FaceVaultLogger.log("Zone captured — \(zone) (\(self.capturedZones.count)/\(self.totalZones))")

            // Animate progress slowly
            self.previewView?.updateProgress(progress)
            
            switch self.capturedZones.count {
            case 1: self.previewView?.showMessage("Move your head slowly...")
            case 2: self.previewView?.showMessage("Keep going...")
            case 3: self.previewView?.showMessage("A little more...")
            case 4: self.previewView?.showMessage("Almost there...")
            case 5:
                self.previewView?.showMessage("✅ Scan complete!")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.finishEnroll(completion: self.enrollCompletion ?? { _ in })
                }
            default: break
            }
        }
    }

    
    private func finishEnroll(completion: @escaping (Bool) -> Void) {
        guard !enrollCompleted else { return }
        enrollCompleted = true
        
        // Stop ARKit first
        liveness.stop()
        
        guard !enrollEmbeddings.isEmpty else {
            FaceVaultLogger.log("Enrollment failed — no frames captured", level: .error)
            previewView?.showMessage("❌ No face detected — try again")
            completion(false)
            return
        }
        
        previewView?.showMessage("✅ Scan complete — verifying identity...")
        
        // Average embeddings
        let avgEmbedding = averageEmbeddings(enrollEmbeddings)
        
        // Save AFTER ARKit stops — no conflict
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            
            // Small delay — let ARKit fully release
            Thread.sleep(forTimeInterval: 0.5)
            
            let saved = self.storage.saveEmbedding(avgEmbedding)
            self.storedEmbedding = avgEmbedding
            FaceVaultLogger.log(saved ? "Enrollment complete — \(self.enrollEmbeddings.count) frames averaged" : "Enrollment failed — could not save embedding", level: saved ? .info : .error)

            
            DispatchQueue.main.async {
                completion(saved)
            }
        }
    }

    private func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else { return [] }
        let size = embeddings[0].count
        var avg = [Float](repeating: 0, count: size)
        
        for embedding in embeddings {
            for i in 0..<size {
                avg[i] += embedding[i]
            }
        }
        
        let count = Float(embeddings.count)
        return avg.map { $0 / count }
    }


    
    public func authenticate(completion: @escaping (FaceVaultResult) -> Void) {
        #if targetEnvironment(simulator)
        completion(.deniedInsufficientData)
        return
        #endif
        FaceVaultLogger.log("Authentication started")

        self.stop()
        
        isEnrolling = false
        onResult = completion
        challengePassed = false
        livenessScore = 0
        currentEmbedding = nil
        liveEmbeddings = []
        
        previewView?.showMessage("🔐 Authenticating...")
        
        // Load embedding in background — show UI immediately
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            
            guard let stored = self.storage.loadEmbedding() else {
                FaceVaultLogger.log("Authentication failed — no enrolled face", level: .error)

                DispatchQueue.main.async { completion(.deniedInsufficientData) }
                return
            }
            
            self.storedEmbedding = stored
            
            DispatchQueue.main.async {
                self.previewView?.showMessage("Position your face in the oval")
                self.liveness.start()
                self.attachLivenessPreview()
            }
        }
    }
    
    private func waitForEmbedding(retryCount: Int = 0, completion: @escaping ([Float]?) -> Void) {
            if let embedding = self.currentEmbedding {
                completion(embedding)
            } else if retryCount < 15 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.waitForEmbedding(retryCount: retryCount + 1, completion: completion)
                }
            } else {
                completion(nil)
            }
    }

    
    public func stop() {
        liveness.stop()
        camera.stop()
        
        // Clean up preview
        DispatchQueue.main.async {
            self.previewView?.reset()
        }
    }

    
    public func attachPreview(_ view: FaceVaultPreviewView) {
        previewView = view
    }
    
    private func attachLivenessPreview() {
        if let session = liveness.captureSession {
            previewView?.attachARSession(session)
        }
    }
    
    // MARK: - Decision
    private func makeDecision() {
        guard let stored = storedEmbedding else {
            DispatchQueue.main.async { [weak self] in
                self?.onResult?(.requiresRetry)
                self?.stop()
            }
            return
        }
        
        let nsB = stored.map { NSNumber(value: $0) }
        
        // Use multi-frame averaging if we have enough frames
        let embeddingScore: Float
        
        if liveEmbeddings.count >= 2 {
            // Average multiple frames
            let nsLive = liveEmbeddings.map { $0.map { NSNumber(value: $0) } }
            embeddingScore = bridge.match(withAveraging: nsLive, stored: nsB)
            FaceVaultLogger.log("Embedding score — \(String(format: "%.2f", embeddingScore)) (\(liveEmbeddings.count) frames averaged)")

        } else if let current = currentEmbedding {
            // Fallback — single frame
            let nsA = current.map { NSNumber(value: $0) }
            embeddingScore = bridge.cosineSimilarity(nsA, b: nsB)
            FaceVaultLogger.log("Embedding score — \(String(format: "%.2f", embeddingScore)) (single frame)")

        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onResult?(.requiresRetry)
                self?.stop()
            }
            return
        }
        
        let input = FaceVaultDecisionInput()
        input.embeddingScore     = embeddingScore
        input.livenessScore      = livenessScore
        input.challengePassed    = challengePassed
        input.singleFaceDetected = singleFaceDetected
        input.landmarkCount      = Int32(landmarkCount)
        
        let engine = FaceVaultDecisionBridge()
        let resultCode = engine.evaluate(input)
        
        let faceVaultResult: FaceVaultResult
        switch resultCode {
        case 0:
            faceVaultResult = .authenticated(confidence: embeddingScore)
            FaceVaultLogger.log("Authenticated — confidence: \(String(format: "%.2f", embeddingScore))")
        case 1:
            faceVaultResult = .deniedLiveness
            FaceVaultLogger.log("Denied — liveness failed", level: .warning)
        case 2:
            faceVaultResult = .deniedNoMatch
            FaceVaultLogger.log("Denied — face does not match", level: .warning)
        case 3:
            faceVaultResult = .deniedMultipleFaces
            FaceVaultLogger.log("Denied — multiple faces", level: .warning)
        case 4:
            faceVaultResult = .deniedInsufficientData
            FaceVaultLogger.log("Denied — insufficient data", level: .warning)
        case 5:
            faceVaultResult = .deniedTampered
            FaceVaultLogger.log("Denied — security violation", level: .error)
        default:
            faceVaultResult = .requiresRetry
        }

        
        DispatchQueue.main.async { [weak self] in
            self?.stop()
            self?.onResult?(faceVaultResult)
        }
    }
}

// MARK: - Vision Delegate
extension FaceVaultSDK: FaceVaultVisionDelegate {
    
    public func vision(_ vision: FaceVaultVision, didDetect landmarks: FaceLandmarks) {
        singleFaceDetected = true
        landmarkCount = landmarks.landmarks.count
        lastLandmarks = landmarks
        
        // Only show landmarks during authenticate, not enroll
//        if !isEnrolling {
//            previewView?.updateLandmarks(landmarks.landmarks, boundingBox: landmarks.boundingBox)
//        } else {
//            previewView?.clearLandmarks() // ← hide during enroll
//        }
        
        previewView?.clearLandmarks()
        previewView?.hideMultipleFacesWarning()

        
        if isEnrolling {
            updateEnrollProgress(yaw: landmarks.yaw, pitch: landmarks.pitch)
        }
    }
    
    public func visionDidLoseFace(_ vision: FaceVaultVision) {
        singleFaceDetected = false
        landmarkCount = 0
        previewView?.clearLandmarks()
        
        if isEnrolling {
            previewView?.showMessage("👤 Please show your face")
        } else {
            previewView?.showAngleWarning()
        }
    }
    
    public func visionDidDetectMultipleFaces(_ vision: FaceVaultVision, count: Int) {
        singleFaceDetected = false
        DispatchQueue.main.async { [weak self] in
            self?.onResult?(.deniedMultipleFaces)
            self?.stop()
        }
    }
}

// MARK: - Liveness Delegate
extension FaceVaultSDK: FaceVaultLivenessDelegate {
    
    public func liveness(_ liveness: FaceVaultLiveness, didUpdate result: LivenessResult) {
            switch result {
            case .passed:
                challengePassed = true
                livenessScore = 1.0
                
                // Use the new non-blocking wait instead of Thread.sleep
                waitForEmbedding { [weak self] embedding in
                    guard let self = self, let validEmbedding = embedding else {
                        DispatchQueue.main.async {
                            self?.onResult?(.requiresRetry)
                            self?.stop()
                        }
                        return
                    }
                    
                    if self.isEnrolling {
                        guard !self.enrollCompleted else { return }
                        self.enrollCompleted = true
                        
                        let saved = self.storage.saveEmbedding(validEmbedding)
                        self.storedEmbedding = validEmbedding
                        
                        DispatchQueue.main.async {
                            self.stop()
                            self.enrollCompletion?(saved)
                        }
                    } else {
                        self.makeDecision()
                    }
                }
            
        case .failed(let reason):
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isEnrolling {
                    self.enrollCompletion?(false)
                } else {
                    self.onResult?(.deniedLiveness)
                }
                self.stop()
            }
            
        case .inProgress:
            break
        }
    }
    
    public func liveness(_ liveness: FaceVaultLiveness, requiresChallenge challenge: LivenessChallenge) {
        previewView?.showChallenge(challenge)
    }
    
    public func liveness(_ liveness: FaceVaultLiveness,
                         didCaptureFrame pixelBuffer: CVPixelBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastEmbeddingTime) > 0.5 else { return }
        lastEmbeddingTime = now
        
        let runBiSeNet = now.timeIntervalSince(lastSegmentTime) > 2.0
        if runBiSeNet { lastSegmentTime = now }
        self.lastPixelBuffer = pixelBuffer
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            
            guard let anchor = self.liveness.latestFaceAnchor else {
                print("❌ latestFaceAnchor is nil")
                return
            }
            print("✅ Got face anchor — \(anchor.geometry.vertices.count) vertices")
            
            let transform = anchor.transform
            let yaw   = atan2(transform.columns.0.z, transform.columns.2.z)
            let pitch = asin(-transform.columns.1.z)
            let roll  = atan2(transform.columns.1.x, transform.columns.1.y)
            
            let vertices = anchor.geometry.vertices
            let leftEyeVertex  = vertices.count > 468 ? vertices[468] : SIMD3<Float>(0.3, 0.5, 0)
            let rightEyeVertex = vertices.count > 473 ? vertices[473] : SIMD3<Float>(0.7, 0.5, 0)
            
            let leftEyeX  = (leftEyeVertex.x + 0.1) / 0.2
            let leftEyeY  = (leftEyeVertex.y + 0.1) / 0.2
            let rightEyeX = (rightEyeVertex.x + 0.1) / 0.2
            let rightEyeY = (rightEyeVertex.y + 0.1) / 0.2
            
            // Build faceRect
            let faceRect = FaceVaultFaceRect()
            faceRect.x             = 0.2
            faceRect.y             = 0.2
            faceRect.width         = 0.6
            faceRect.height        = 0.6
            faceRect.yaw           = yaw
            faceRect.pitch         = pitch
            faceRect.roll          = roll
            faceRect.landmarkCount = Int32(vertices.count)
            faceRect.leftEyeX      = leftEyeX
            faceRect.leftEyeY      = leftEyeY
            faceRect.rightEyeX     = rightEyeX
            faceRect.rightEyeY     = rightEyeY
            
            // Now process
            guard let result = self.preprocessor.process(pixelBuffer,
                                                          faceRect: faceRect) else {
                print("❌ Preprocessor returned nil")
                return
            }
            
            print("📊 Preprocessor — success:\(result.success) tooFar:\(result.tooFar) tooClose:\(result.tooClose) quality:\(result.qualityScore)")
            
            guard result.success else {
                print("❌ Preprocessor failed — \(result.error ?? "unknown")")
                return
            }
            
            if result.tooFar {
                DispatchQueue.main.async { self.previewView?.showMessage("Move closer") }
                return
            }
            if result.tooClose {
                DispatchQueue.main.async { self.previewView?.showMessage("Move further away") }
                return
            }
            
            let bufferToUse: CVPixelBuffer
            if let processed = result.processedBuffer {
                bufferToUse = processed
            } else {
                bufferToUse = pixelBuffer
            }
            
            let finalBuffer: CVPixelBuffer
            if runBiSeNet,
               let _ = self.segmentorML.generateMask(from: bufferToUse) {
                finalBuffer = bufferToUse
            } else {
                finalBuffer = bufferToUse
            }
            
            guard let embedding = self.embedder.generateEmbedding(from: finalBuffer) else {
                print("❌ Embedding failed")
                return
            }
            
            print("✅ Embedding generated — IR pipeline")
            print("🔵 isEnrolling = \(self.isEnrolling)")

            if self.isEnrolling {
                guard self.enrollEmbeddings.count < self.maxEnrollFrames else { return }
                self.enrollEmbeddings.append(embedding)
                print("✅ Enroll frame \(self.enrollEmbeddings.count)/\(self.maxEnrollFrames)")
            } else {
                guard self.liveEmbeddings.count < self.maxLiveFrames else { return }
                self.liveEmbeddings.append(embedding)
                self.currentEmbedding = embedding
                print("✅ Live frame \(self.liveEmbeddings.count)/\(self.maxLiveFrames)")
            }
        }
    }

    
    public static func enableLogging() {
        FaceVaultLogger.isEnabled = true
        FaceVaultLogger.log("FaceVault SDK — logging enabled")
    }

    
    public func estimateAge(threshold: Int = 18,
                             completion: @escaping (FaceVaultAgeResult?) -> Void) {
        guard let pixelBuffer = lastPixelBuffer else {
            FaceVaultLogger.log("Age estimation failed — no pixel buffer", level: .warning)

            completion(nil)
            return
        }
        FaceVaultLogger.log("Pixel buffer stored for age estimation")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.ageEstimator.estimateAge(from: pixelBuffer,
                                                        threshold: threshold)
            if let r = result {
                FaceVaultLogger.log("Age estimate — \(String(format: "%.1f", r.estimatedAge)) years | range: \(r.ageRange) | adult: \(r.isAdult)")
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    public func stopContinuousAuth() {
        continuousAuth.stop()
    }
    
    // 1 minute = 60 seconds
    // 2 minutes = 120 seconds
    // Let developer decide — default 2 minutes

    public func startContinuousAuth(interval: TimeInterval = 5.0,
                                     threshold: Float = 0.75,
                                     maxDuration: TimeInterval = 120.0,
                                     onEvent: @escaping (ContinuousAuthEvent) -> Void) {
        guard let stored = storedEmbedding else {
            FaceVaultLogger.log("Continuous auth failed — no stored embedding", level: .error)

            return
        }
        
        let handler = ContinuousAuthHandler(onEvent: onEvent)
        continuousAuth.delegate = handler
        objc_setAssociatedObject(self,
                                  &FaceVaultSDK.continuousAuthHandlerKey,
                                  handler,
                                  .OBJC_ASSOCIATION_RETAIN)
        
        // Handle when continuous auth stops
        continuousAuth.onStopped = {
        }
        
        continuousAuth.start(storedEmbedding: stored,
                              interval: interval,
                              threshold: threshold,
                              maxDuration: maxDuration)
    }

    public func liveness(_ liveness: FaceVaultLiveness,
                         didUpdateHeadPose yaw: Float, pitch: Float) {
        if isEnrolling {
            updateEnrollProgress(yaw: yaw, pitch: pitch)
        }
    }
    
    // Add to FaceVaultLivenessDelegate conformance
    public func liveness(_ liveness: FaceVaultLiveness,
                         didDetectFaceAnchor anchor: ARFaceAnchor) {
        
        singleFaceDetected = true
        
        // Get viewport size
        let viewportSize = previewView?.bounds.size ?? CGSize(width: 1440, height: 1080)
        
        // Create IR landmarks
        let irLandmarks = FaceVaultIRLandmarks(
            anchor: anchor,
            viewportSize: viewportSize
        )
        
        landmarkCount = irLandmarks.landmarkCount
        
        // Build face rect from IR data
        lastIRLandmarks = irLandmarks
        
        previewView?.clearLandmarks()
        previewView?.hideMultipleFacesWarning()
        
        if isEnrolling {
            updateEnrollProgress(
                yaw: irLandmarks.yaw,
                pitch: irLandmarks.pitch
            )
        }
    }

    public func livenessDidLoseFace(_ liveness: FaceVaultLiveness) {
        singleFaceDetected = false
        landmarkCount = 0
        lastIRLandmarks = nil
        previewView?.clearLandmarks()
        
        if isEnrolling {
            previewView?.showMessage("Please show your face")
        } else {
            previewView?.showAngleWarning()
        }
    }
}

extension FaceVaultSDK: FaceVaultCameraDelegate {
    public func camera(_ camera: FaceVaultCamera, didOutput sampleBuffer: CMSampleBuffer) {
        guard isEnrolling else { return }
        guard enrollEmbeddings.count < maxEnrollFrames else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        vision.process(sampleBuffer: sampleBuffer)  // ← use sampleBuffer not pixelBuffer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            
            // Run Vision
            self.vision.process(pixelBuffer: pixelBuffer)
            
            guard let landmarks = self.lastLandmarks else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("👤 No face detected")
                }
                return
            }
            
            // ✅ Check 1 — Single face only
            guard self.singleFaceDetected else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("⚠️ Multiple faces detected")
                }
                return
            }
            
            // ✅ Check 2 — Head angle
            guard abs(landmarks.yaw)   < 0.3 &&
                  abs(landmarks.pitch) < 0.3 &&
                  abs(landmarks.roll)  < 0.3 else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("⚠️ Face the camera directly")
                }
                return
            }
            
            // ✅ Check 3 — Enough landmarks
            guard landmarks.landmarks.count >= 50 else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("⚠️ Poor face visibility")
                }
                return
            }
            
            // Build face rect
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
            
            // ✅ Check 4 — C++ preprocessor (distance + quality)
            guard let result = self.preprocessor.process(pixelBuffer, faceRect: faceRect) else {
                return
            }
            
            // ✅ Check 5 — Distance
            if result.tooFar {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("📏 Move closer")
                }
                return
            }
            
            if result.tooClose {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("📏 Move further away")
                }
                return
            }
            
            // ✅ Check 6 — Quality score
            guard result.qualityScore >= 0.5 else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("⚠️ Poor image quality")
                }
                return
            }
            
            // ✅ Check 7 — Both eyes open
            // Eyes open = blink value LOW
            // We check via landmarks eye aspect ratio
            let leftEye  = landmarks.leftEye
            let rightEye = landmarks.rightEye
            let eyeDist  = sqrt(pow(rightEye.x - leftEye.x, 2) +
                               pow(rightEye.y - leftEye.y, 2))
            guard eyeDist > 0.05 else {
                DispatchQueue.main.async {
                    self.previewView?.showMessage("👁 Please open both eyes")
                }
                return
            }
            
            // ✅ All checks passed — generate embedding
            guard result.success else { return }
            
            guard let processedBuffer = result.processedBuffer else {
                // Fallback to original
                guard let embedding = self.embedder.generateEmbedding(from: pixelBuffer) else { return }
                self.enrollEmbeddings.append(embedding)
                return
            }

            guard let embedding = self.embedder.generateEmbedding(from: processedBuffer) else { return }
            self.enrollEmbeddings.append(embedding)

//            let count = self.enrollEmbeddings.count
//            
//            DispatchQueue.main.async {
//                self.previewView?.showMessage("✅ Scanning \(count)/\(self.maxEnrollFrames)")
//            }
        }
    }
}

// MARK: - Closure wrapper for continuous auth delegate
private class ContinuousAuthHandler: NSObject, FaceVaultContinuousAuthDelegate {
    let onEvent: (ContinuousAuthEvent) -> Void
    init(onEvent: @escaping (ContinuousAuthEvent) -> Void) {
        self.onEvent = onEvent
    }
    func continuousAuth(_ auth: FaceVaultContinuousAuth,
                        didDetect event: ContinuousAuthEvent) {
        onEvent(event)
    }
}
