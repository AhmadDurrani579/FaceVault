//
//  FaceVaultCamera.swift
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

import AVFoundation
import CoreMedia

public protocol FaceVaultCameraDelegate: AnyObject {
    func camera(_ camera: FaceVaultCamera, didOutput sampleBuffer: CMSampleBuffer)
}

public class FaceVaultCamera: NSObject {
    
    // MARK: - Properties
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.facevault.camera", qos: .userInteractive)
    
    public weak var delegate: FaceVaultCameraDelegate?
    public private(set) var isRunning = false
    
    public var captureSession: AVCaptureSession {
        return session
    }

    // MARK: - Init
    public override init() {
        super.init()
//        setupSession()
    }
    
    // MARK: - Setup
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .front) else {
            print("FaceVault: Front camera not available")
            session.commitConfiguration()
            return
        }
        
        do {
            try device.lockForConfiguration()
            
            // Find highest supported frame rate
            let supportedRanges = device.activeFormat.videoSupportedFrameRateRanges
            let maxFrameRate = supportedRanges.map { $0.maxFrameRate }.max() ?? 30
            let targetFrameRate = min(60, maxFrameRate)
            
            let duration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            print("❌ FaceVault: Could not set frame rate — \(error)")
        }
        
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        
        session.commitConfiguration()
        print("✅ FaceVault: Camera session configured")
    }
    
    // MARK: - Control
    public func start() {

        #if targetEnvironment(simulator)
        print("⚠️ FaceVault: Camera not available on simulator")
        return
        #endif
        
        setupSession() // ← move here, only setup when actually needed
        
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInteractive).async {
            self.session.startRunning()
            self.isRunning = true
            print("✅ FaceVault: Camera started")
        }
    }

    
    public func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInteractive).async {
            self.session.stopRunning()
            self.isRunning = false
            print("✅ FaceVault: Camera stopped")
        }
    }
    
}

// MARK: - Sample Buffer Delegate
extension FaceVaultCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ output: AVCaptureOutput,
                               didOutput sampleBuffer: CMSampleBuffer,
                               from connection: AVCaptureConnection) {
        delegate?.camera(self, didOutput: sampleBuffer)
    }
    
    public func captureOutput(_ output: AVCaptureOutput,
                               didDrop sampleBuffer: CMSampleBuffer,
                               from connection: AVCaptureConnection) {
        print("FaceVault: Frame dropped")
    }
}
