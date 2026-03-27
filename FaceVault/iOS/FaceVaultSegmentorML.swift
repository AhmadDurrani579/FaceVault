//
//  FaceVaultSegmentorML.swift
//  FaceVault
//
//  Created by Ahmad on 26/03/2026.
//

import CoreML
import CoreImage
import UIKit

public class FaceVaultSegmentorML{
    private var model: MLModel?
    
    public init() {
        loadModel()
    }
    
    private func loadModel() {
        let bundle = Bundle(for: FaceVaultSegmentorML.self)
        
        let modelURL = bundle.url(forResource: "FaceVaultSegmentor", withExtension: "mlpackage")
                    ?? bundle.url(forResource: "FaceVaultSegmentor", withExtension: "mlmodelc")
        
        guard let url = modelURL else {
            FaceVaultLogger.log("BiSeNet segmentor not found in bundle", level: .error)
            return
        }
        
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            model = try MLModel(contentsOf: url, configuration: config)
            FaceVaultLogger.log("BiSeNet segmentor loaded — 19 class face parsing")
        } catch {
            FaceVaultLogger.log("BiSeNet segmentor failed to load — \(error.localizedDescription)", level: .error)
        }
    }
    
    // MARK: - Generate Mask
    // Returns binary mask — 1 = face, 0 = background
    public func generateMask(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let model else {
            print("❌ FaceVault: Segmentor model not loaded")
            return nil
        }
        
        // Resize to 512x512
        guard let resized = resize(pixelBuffer: pixelBuffer,
                                    to: CGSize(width: 512, height: 512)) else {
            return nil
        }
        
        do {
            // Convert to MLMultiArray (1, 3, 512, 512)
            let array = try MLMultiArray(shape: [1, 3, 512, 512],
                                          dataType: .float32)
            
            CVPixelBufferLockBaseAddress(resized, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(resized, .readOnly) }
            
            let width  = CVPixelBufferGetWidth(resized)
            let height = CVPixelBufferGetHeight(resized)
            guard let base = CVPixelBufferGetBaseAddress(resized) else { return nil }
            let rowBytes = CVPixelBufferGetBytesPerRow(resized)
            let buffer = base.assumingMemoryBound(to: UInt8.self)
            
            // Normalize with ImageNet mean/std
            let mean: [Float] = [0.485, 0.456, 0.406]
            let std:  [Float] = [0.229, 0.224, 0.225]
            
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * rowBytes + x * 4
                    let b = Float(buffer[offset])     / 255.0
                    let g = Float(buffer[offset + 1]) / 255.0
                    let r = Float(buffer[offset + 2]) / 255.0
                    
                    array[[0, 0, y, x] as [NSNumber]] = NSNumber(value: (r - mean[0]) / std[0])
                    array[[0, 1, y, x] as [NSNumber]] = NSNumber(value: (g - mean[1]) / std[1])
                    array[[0, 2, y, x] as [NSNumber]] = NSNumber(value: (b - mean[2]) / std[2])
                }
            }
            
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "faceInput": MLFeatureValue(multiArray: array)
            ])
            
            let output = try model.prediction(from: input)
            
            // Get segmentation output — var_621
            guard let segOutput = output.featureValue(for: "var_621")?.multiArrayValue else {
                print("❌ FaceVault: No segmentation output")
                // Print available outputs
                output.featureNames.forEach { print("📤 Available: \($0)") }
                return nil
            }
            // Convert to binary mask
            return buildMask(from: segOutput, size: 512)
            
        } catch {
            print("❌ FaceVault: Segmentation inference failed — \(error)")
            return nil
        }
    }
    
    // MARK: - Build Binary Mask
    // BiSeNet outputs 19 classes:
    // 0=background, 1=skin, 2=left brow, 3=right brow,
    // 4=left eye, 5=right eye, 6=glasses, 7=left ear,
    // 8=right ear, 9=earring, 10=nose, 11=mouth,
    // 12=upper lip, 13=lower lip, 14=neck, 15=necklace,
    // 16=cloth, 17=hair, 18=hat
    private func buildMask(from output: MLMultiArray, size: Int) -> CVPixelBuffer? {
        var maskBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, size, size,
                            kCVPixelFormatType_OneComponent8,
                            nil, &maskBuffer)
        
        guard let mask = maskBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(mask, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(mask, CVPixelBufferLockFlags(rawValue: 0)) }
        
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let dst = base.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        
        // Face classes — skin + eyes + nose + mouth + eyebrows
        let faceClasses: Set<Int> = [1, 2, 3, 4, 5, 10, 11, 12, 13]
        
        let channels = 19
        
        for y in 0..<size {
            for x in 0..<size {
                // Find class with highest score
                var maxScore: Float = -Float.infinity
                var maxClass = 0
                
                for c in 0..<channels {
                    let idx = c * size * size + y * size + x
                    let score = output[idx].floatValue
                    if score > maxScore {
                        maxScore = score
                        maxClass = c
                    }
                }
                
                // Write mask
                dst[y * rowBytes + x] = faceClasses.contains(maxClass) ? 255 : 0
            }
        }
        
        return mask
    }
    
    // MARK: - Resize Helper
    private func resize(pixelBuffer: CVPixelBuffer,
                        to size: CGSize) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX = size.width  / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let scaleY = size.height / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        var output: CVPixelBuffer?
        CVPixelBufferCreate(nil,
                            Int(size.width), Int(size.height),
                            kCVPixelFormatType_32BGRA,
                            nil, &output)
        
        guard let out = output else { return nil }
        CIContext().render(scaled, to: out)
        return out
    }


}
