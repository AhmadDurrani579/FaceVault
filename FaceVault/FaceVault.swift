//
//  FaceVault.swift
//  FaceVault
//
//  Created by Ahmad on 24/03/2026.
//

import Foundation


public class FaceVaultSDK {
    private let bridge = FaceVaultMatcherBridge()

    public init() {}
    
    public func similarity(_ a: [Float], _ b: [Float]) -> Float {
        let nsA = a.map { NSNumber(value: $0) }
        let nsB = b.map { NSNumber(value: $0) }
        return bridge.cosineSimilarity(nsA, b: nsB)
    }
    
    public func isMatch(_ a: [Float], _ b: [Float], threshold: Float = 0.75) -> Bool {
        let nsA = a.map { NSNumber(value: $0) }
        let nsB = b.map { NSNumber(value: $0) }
        return bridge.isMatch(nsA, b: nsB, threshold: threshold)
    }

}

