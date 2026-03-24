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
        loadModel()
    }
    
    private func loadModel() {
        guard let modelURL = Bundle(for: FaceVaultEmbedder.self)
                .url(forResource: "FaceVault", withExtension: "mlmodelc") else {
            print("FaceVault: Could not find FaceVaultEmbedder.mlpackage")
            return
        }
        
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            model = try MLModel(contentsOf: modelURL, configuration: config)
            printf("FaceVault: Embedding model loaded")
        } catch {
            printf("FaceVault: Failed to load model — \(error)")
        }
    }
    
    public func generateEmbedding(from pixelBuffer: CVPixelBuffer) -> [Float]? {
        guard let model else {
            print("FaceVault: Model not loaded")
            return nil
        }
        
        // Resize to 160x160
        guard let resized = resize(pixelBuffer: pixelBuffer, to: CGSize(width: 160, height: 160)) else {
            print("FaceVault: Could not resize image")
            return nil
        }
        guard let input = try? MLDictionaryFeatureProvider(dictionary: ["faceInput": MLFeatureValue(pixelBuffer: resized)]),
              let output = try? model.prediction(from: input),
              let embedding = output.featureValue(for: "embedding")?.multiArrayValue else {
            print("FaceVault: Inference failed")
            return nil
        }
        
        // Convert MLMultiArray → [Float]
        let length = embedding.count
        var result = [Float](repeating: 0, count: length)
        for i in 0..<length {
            result[i] = embedding[i].floatValue
        }
        
        print("FaceVault: Embedding generated — \(length) dims")
        return result

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

