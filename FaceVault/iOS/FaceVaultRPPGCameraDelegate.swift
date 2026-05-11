//
//  FaceVaultRPPGCameraDelegate.swift
//  FaceVault
//
//  Created by Ahmad on 26/04/2026.
//


import AVFoundation
import CoreMedia

protocol FaceVaultRPPGCameraDelegate: AnyObject {
    func rPPGCamera(_ camera: FaceVaultRPPGCamera,
                    didOutput sampleBuffer: CMSampleBuffer)
}

class FaceVaultRPPGCamera: NSObject {
    
    public let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.facevault.rppg",
                                      qos: .background)
    
    weak var delegate: FaceVaultRPPGCameraDelegate?
    private(set) var isRunning = false
    
    static func isFrontCameraAvailable() -> Bool {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ),
        let input = try? AVCaptureDeviceInput(device: device),
        session.canAddInput(input) else { return false }
        return true
    }

    func start() {
        guard !isRunning else { return }
        
        queue.async { [weak self] in
            guard let self else { return }
            
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .medium
            
            // Front camera
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
            ) else { return }
            
            // 24fps fixed
            do {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 24)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 24)
                device.unlockForConfiguration()
            } catch { return }
            
            guard let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else { return }
            self.captureSession.addInput(input)
            
            self.videoOutput.setSampleBufferDelegate(
                self, queue: self.queue
            )
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_32BGRA
            ]
            
            guard self.captureSession.canAddOutput(self.videoOutput) else { return }
            self.captureSession.addOutput(self.videoOutput)
            
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
            self.isRunning = true
        }
    }
    
    func stop(completion: (() -> Void)? = nil) {
        guard isRunning else {
            completion?()
            return
        }
        queue.async { [weak self] in
            self?.captureSession.stopRunning()
            self?.isRunning = false
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
}

extension FaceVaultRPPGCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        delegate?.rPPGCamera(self, didOutput: sampleBuffer)
    }
}
