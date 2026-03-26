//
//  FaceVaultEmbedder.swift
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//
import CoreML
import Vision
import CoreImage
import UIKit

public class FaceVaultEmbedder {
    
    private var model: MLModel?
    public init() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.loadModel()
        }

    }
    
    private func loadModel() {
        let bundle = Bundle(for: FaceVaultEmbedder.self)
        
        let modelURL = bundle.url(forResource: "FaceVaultEmbedder", withExtension: "mlpackage")
                    ?? bundle.url(forResource: "FaceVaultEmbedder", withExtension: "mlmodelc")
        
        guard let url = modelURL else {
            print(" FaceVault: Could not find embedding model")
            return
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            model = try MLModel(contentsOf: url, configuration: config)
            print("✅ FaceVault: Embedding model loaded from \(url.lastPathComponent)")
            model?.modelDescription.inputDescriptionsByName.forEach { name, desc in
                print("📥 Model input: \(name) — \(desc.type)")
            }

            model?.modelDescription.outputDescriptionsByName.forEach { name, desc in
                print("📤 Model output: \(name) — \(desc.type)")
            }

        } catch {
            print(" FaceVault: Failed to load model — \(error)")
        }
    }

    
    public func generateEmbedding(from pixelBuffer: CVPixelBuffer) -> [Float]? {
        guard let model else { return nil }
        
        guard let resized = resize(pixelBuffer: pixelBuffer, to: CGSize(width: 112, height: 112)) else {
            print("❌ FaceVault: Could not resize")
            return nil
        }
        
        do {
            // Convert pixel buffer → MLMultiArray (1, 3, 160, 160)
            let array = try MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32)
            
            CVPixelBufferLockBaseAddress(resized, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(resized, .readOnly) }
            
            let width = CVPixelBufferGetWidth(resized)
            let height = CVPixelBufferGetHeight(resized)
            guard let baseAddress = CVPixelBufferGetBaseAddress(resized) else { return nil }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(resized)
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    let b = Float(buffer[offset])     / 255.0
                    let g = Float(buffer[offset + 1]) / 255.0
                    let r = Float(buffer[offset + 2]) / 255.0
                    
                    array[[0, 0, y, x] as [NSNumber]] = NSNumber(value: r)
                    array[[0, 1, y, x] as [NSNumber]] = NSNumber(value: g)
                    array[[0, 2, y, x] as [NSNumber]] = NSNumber(value: b)
                }
            }
            
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "faceInput": MLFeatureValue(multiArray: array)
            ])
            
            let output = try model.prediction(from: input)
            
            guard let embedding = output.featureValue(for: "embedding")?.multiArrayValue else {
                print("❌ FaceVault: No embedding in output")
                return nil
            }
            
            let length = embedding.count
            var result = [Float](repeating: 0, count: length)
            for i in 0..<length {
                result[i] = embedding[i].floatValue
            }
            
            print("✅ FaceVault: Embedding generated — \(length) dims")
            return result
            
        } catch {
            print("❌ FaceVault: Inference failed — \(error)")
            return nil
        }
    }
    
    // MARK: - Resize Helper
    private func resize(pixelBuffer: CVPixelBuffer, to size: CGSize) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX = size.width / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let scaleY = size.height / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        var output: CVPixelBuffer?
        CVPixelBufferCreate(nil,
                            Int(size.width),
                            Int(size.height),
                            kCVPixelFormatType_32BGRA,
                            nil,
                            &output)
        guard let out = output else { return nil }
        CIContext().render(scaled, to: out)
        return out
    }

}

