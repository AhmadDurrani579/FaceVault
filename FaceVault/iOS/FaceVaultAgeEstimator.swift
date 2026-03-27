//
//  FaceVaultAgeBridge.swift
//  FaceVault
//
//  Created by Ahmad on 26/03/2026.
//

import CoreML
import CoreImage
import UIKit

// MARK: - Public Age Result
public struct FaceVaultAgeResult {
    public let estimatedAge: Float
    public let ageRange: String
    public let isAdult: Bool
    public let confidence: Float
    public let ageThreshold: Int
    public let success: Bool
    public let error: String?
}

// MARK: - Age Estimator
public class FaceVaultAgeEngine {
    
    private var model: MLModel?
    private var ageEstimates: [Float] = []
    private let maxEstimates = 5
    
    public init() {
        loadModel()
    }
    
    // MARK: - Load Model
    private func loadModel() {
        let bundle = Bundle(for: FaceVaultAgeEngine.self)
        
        let modelURL = bundle.url(forResource: "FaceVaultAgeEstimator",
                                   withExtension: "mlpackage")
                    ?? bundle.url(forResource: "FaceVaultAgeEstimator",
                                   withExtension: "mlmodelc")
        
        guard let url = modelURL else {
            print("❌ FaceVault: Age model not found")
            return
        }
        
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            model = try MLModel(contentsOf: url, configuration: config)
            print("✅ FaceVault: Age estimator loaded")
        } catch {
            print("❌ FaceVault: Failed to load age model — \(error)")
        }
    }
    
    // MARK: - Estimate Age
    public func estimateAge(from pixelBuffer: CVPixelBuffer,
                             threshold: Int = 18) -> FaceVaultAgeResult? {
        guard let model else {
            print("❌ FaceVault: Age model not loaded")
            return nil
        }
        
        // Resize to 224x224
        guard let resized = resize(pixelBuffer: pixelBuffer,
                                    to: CGSize(width: 96, height: 96)) else {
            return nil
        }
        
        do {
            // Convert to MLMultiArray
            let array = try MLMultiArray(shape: [1, 3, 96, 96],
                                          dataType: .float32)
            
            CVPixelBufferLockBaseAddress(resized, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(resized, .readOnly) }
            
            let width    = CVPixelBufferGetWidth(resized)
            let height   = CVPixelBufferGetHeight(resized)
            let rowBytes = CVPixelBufferGetBytesPerRow(resized)
            guard let base = CVPixelBufferGetBaseAddress(resized) else { return nil }
            let buffer = base.assumingMemoryBound(to: UInt8.self)
            
            // ImageNet normalization
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
            
            guard let ageOutput = output.featureValue(for: "var_771")?.multiArrayValue else {
                print("❌ FaceVault: No age output")
                return nil
            }
            // InsightFace — index 0 = gender, index 1 = age normalized 0-1
            let genderProb = ageOutput[0].floatValue
            let normalizedAge = ageOutput[2].floatValue  // ← index 2
            let realAge = normalizedAge * 100.0

            print("📊 FaceVault: Gender prob: \(genderProb) Age: \(realAge)")

            // Collect for smoothing
            ageEstimates.append(realAge)
            if ageEstimates.count > maxEstimates {
                ageEstimates.removeFirst()
            }

            let smoothed = smoothAge(ageEstimates)
            let result = evaluateAge(smoothed, threshold: threshold)
            return result
            
        } catch {
            print("❌ FaceVault: Age inference failed — \(error)")
            return nil
        }
    }
    
    // MARK: - Smooth + Evaluate via C++
    private func smoothAge(_ estimates: [Float]) -> Float {
        guard !estimates.isEmpty else { return 0 }
        let sorted = estimates.sorted()
        let trimmed = sorted.count >= 5 ?
            Array(sorted[1..<sorted.count-1]) : sorted
        return trimmed.reduce(0, +) / Float(trimmed.count)
    }
    
    private func evaluateAge(_ age: Float, threshold: Int) -> FaceVaultAgeResult {
        let isAdult   = age >= Float(threshold)
        let distance  = abs(age - Float(threshold))
        
        let confidence: Float
        if distance < 2.0 { confidence = 0.3 }
        else if distance < 4.0 { confidence = 0.6 }
        else if distance < 6.0 { confidence = 0.8 }
        else { confidence = 0.95 }
        
        let ageRange: String
        if age < 13      { ageRange = "0-12" }
        else if age < 18 { ageRange = "13-17" }
        else if age < 25 { ageRange = "18-24" }
        else if age < 35 { ageRange = "25-34" }
        else if age < 45 { ageRange = "35-44" }
        else if age < 55 { ageRange = "45-54" }
        else if age < 65 { ageRange = "55-64" }
        else             { ageRange = "65+" }
        
        return FaceVaultAgeResult(
            estimatedAge: age,
            ageRange:     ageRange,
            isAdult:      isAdult,
            confidence:   confidence,
            ageThreshold: threshold,
            success:      true,
            error:        nil
        )
    }
    
    // MARK: - Resize
    private func resize(pixelBuffer: CVPixelBuffer,
                        to size: CGSize) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX  = size.width  / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let scaleY  = size.height / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaled  = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX,
                                                                  y: scaleY))
        var output: CVPixelBuffer?
        CVPixelBufferCreate(nil,
                            Int(size.width), Int(size.height),
                            kCVPixelFormatType_32BGRA,
                            nil, &output)
        guard let out = output else { return nil }
        CIContext().render(scaled, to: out)
        return out
    }
    
    // MARK: - Reset
    public func reset() {
        ageEstimates.removeAll()
    }
}
