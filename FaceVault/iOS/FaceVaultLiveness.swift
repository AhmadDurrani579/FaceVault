//
//  FaceVaultLiveness.swift
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

import ARKit
import Foundation

// MARK: - Challenge Types
public enum LivenessChallenge {
    case blink
    case turnLeft
    case turnRight
    case smile
    case openMouth
}

// MARK: - Liveness Result
public enum LivenessResult {
    case passed
    case failed(reason: String)
    case inProgress(challenge: LivenessChallenge)
}

// MARK: - Delegate
public protocol FaceVaultLivenessDelegate: AnyObject {
    func liveness(_ liveness: FaceVaultLiveness, didUpdate result: LivenessResult)
    func liveness(_ liveness: FaceVaultLiveness, requiresChallenge challenge: LivenessChallenge)
    func liveness(_ liveness: FaceVaultLiveness, didCaptureFrame pixelBuffer: CVPixelBuffer)
    func liveness(_ liveness: FaceVaultLiveness, didUpdateHeadPose yaw: Float, pitch: Float)
}

// MARK: - FaceVaultLiveness
public class FaceVaultLiveness: NSObject {
    
    // MARK: - Properties
    private var session: ARSession?
    public weak var delegate: FaceVaultLivenessDelegate?
    
    private var currentChallenge: LivenessChallenge?
    private var challengeStartTime: Date?
    private let challengeTimeout: TimeInterval = 8.0
    
    // Blend shape thresholds
    private let blinkThreshold: Float        = 0.8
    private let smileThreshold: Float        = 0.6
    private let turnThreshold: Float         = 0.3
    private let openMouthThreshold: Float    = 0.5
    
    // Challenge sequence
    private var challengeQueue: [LivenessChallenge] = []
    private var completedChallenges: [LivenessChallenge] = []
    
    public private(set) var isRunning = false
    
    // MARK: - Init
    
    public var captureSession: ARSession? {
        return session
    }

    public override init() {
        super.init()
    }
    
    // MARK: - Start
    public func start() {
        #if targetEnvironment(simulator)
        print("⚠️ FaceVault: ARKit not available on simulator")
        return
        #endif
        
        guard ARFaceTrackingConfiguration.isSupported else {
            return
        }
        
        session = ARSession()
        session?.delegate = self
        session?.delegateQueue = DispatchQueue(label: "com.facevault.arkit", qos: .userInteractive)
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        session?.run(config)
        
        isRunning = true
        generateChallengeQueue()
    }
    
    // MARK: - Stop
    public func stop() {
        session?.pause()
        session = nil
        isRunning = false
    }
    
    // MARK: - Generate Random Challenge Queue
    private func generateChallengeQueue() {
        let all: [LivenessChallenge] = [.blink, .turnLeft, .turnRight, .smile, .openMouth]
        // Always pick exactly 3 — shuffle and take first 3
        challengeQueue = all.shuffled()
        completedChallenges = []
        startNextChallenge()
    }
    
    private func startNextChallenge() {
        guard let next = challengeQueue.first else {
            // All challenges passed
            delegate?.liveness(self, didUpdate: .passed)
            return
        }
        
        currentChallenge = next
        challengeStartTime = Date()
        challengeQueue.removeFirst()
        
        delegate?.liveness(self, requiresChallenge: next)
        delegate?.liveness(self, didUpdate: .inProgress(challenge: next))
    }
    
    public func startEnrollMode() {
        #if targetEnvironment(simulator)
        return
        #endif
        
        guard ARFaceTrackingConfiguration.isSupported else { return }
        
        session = ARSession()
        session?.delegate = self
        session?.delegateQueue = DispatchQueue(label: "com.facevault.arkit",
                                               qos: .userInteractive)
        
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        session?.run(config)
        
        isRunning = true
        // No challenges — just start session
    }
    
    // MARK: - Evaluate Blend Shapes
    private func evaluate(blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber], headYaw: Float = 0) {
        guard let challenge = currentChallenge,
              let startTime = challengeStartTime else { return }
        
        if Date().timeIntervalSince(startTime) > challengeTimeout {
            delegate?.liveness(self, didUpdate: .failed(reason: "Challenge timed out"))
            stop()
            return
        }
        
        var passed = false
        
        switch challenge {
        case .blink:
            let left  = blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
            let right = blendShapes[.eyeBlinkRight]?.floatValue ?? 0
            passed = left > blinkThreshold && right > blinkThreshold
            
        case .turnLeft:
            passed = headYaw > turnThreshold
            
        case .turnRight:
            passed = headYaw < -turnThreshold
            
        case .smile:
            let left  = blendShapes[.mouthSmileLeft]?.floatValue ?? 0
            let right = blendShapes[.mouthSmileRight]?.floatValue ?? 0
            passed = left > smileThreshold && right > smileThreshold
            
        case .openMouth:
            let jaw = blendShapes[.jawOpen]?.floatValue ?? 0
            passed = jaw > openMouthThreshold
        }
        
        if passed {
            completedChallenges.append(challenge)
            currentChallenge = nil
            startNextChallenge()
        }
    }
}

// MARK: - ARSession Delegate
extension FaceVaultLiveness: ARSessionDelegate {
    
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        
        let blendShapes = faceAnchor.blendShapes
        let frame = session.currentFrame
        
        // Get yaw and pitch from ARKit transform
        let transform = faceAnchor.transform
        let yaw   = atan2(transform.columns.0.z, transform.columns.2.z)
        let pitch = asin(-transform.columns.1.z)
        
        // Pass head pose to delegate
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.liveness(self!, didUpdateHeadPose: yaw, pitch: pitch)
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if let pixelBuffer = frame?.capturedImage {
                self.delegate?.liveness(self, didCaptureFrame: pixelBuffer)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.evaluate(blendShapes: blendShapes, headYaw: yaw)
        }
    }

    
    public func session(_ session: ARSession, didFailWithError error: Error) {
        delegate?.liveness(self, didUpdate: .failed(reason: error.localizedDescription))
    }
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Use ARKit frame for Vision + Embedding instead of AVFoundation
//        let pixelBuffer = frame.capturedImage
//        delegate?.liveness(self, didCaptureFrame: pixelBuffer)
    }

}
