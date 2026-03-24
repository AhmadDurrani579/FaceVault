//
//  FaceVaultCamera.swift
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

import AVFoundation
import CoreMedia

public protocol FaceVaultCameraDelegte: AnyObject {
    func camera(_ camera: FaceVaultCamera, didOutput sampleBuffer: CMSampleBuffer)
}

public class FacultVaultCamer: NSObject {
    
    // MARK: - Properties

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.facevault.camera", qos: .userInteractive)
    
    public weak var delegate: FaceVaultCameraDelegte?
    
    public private(set) var isRunning = false

    public overridde init() {
        super.init()
        setUpSession()
        
    }
    
    // MARK: - Setup
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        
        // Front camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .front) else {
            print("FaceVault: Front camera not available")
            session.commitConfiguration()
            return
        }
        
        // 60fps
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
            device.unlockForConfiguration()
        } catch {
            print("FaceVault: Could not set frame rate — \(error)")
        }
        
        // Add input
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("FaceVault: Could not add camera input")
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        
        // Add output
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        
        guard session.canAddOutput(output) else {
            print("FaceVault: Could not add video output")
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        
        // Portrait orientation
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        
        session.commitConfiguration()
        print("FaceVault: Camera session configured")
    }

    
    public func start() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.session.startRunning()
            self?.isRunning = true
            print("FaceVault: Camera started")
        }
    }
    
    public func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInteractive).async {[weak self] in
            self?.session.stopRunning()
            self?.isRunning = false
            print("FaceVault: Camera stopped")
        }
    }
}

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

