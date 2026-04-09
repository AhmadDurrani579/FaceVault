//
//  FaceVaultIRLandmarks.swift
//  FaceVault
//
//  Created by Ahmad on 09/04/2026.
//


import ARKit

public struct FaceVaultIRLandmarks {
    
    // Head pose from ARKit transform
    public let yaw: Float
    public let pitch: Float
    public let roll: Float
    
    // Eye positions from face anchor geometry
    public let leftEyePosition: SIMD3<Float>
    public let rightEyePosition: SIMD3<Float>
    
    // Bounding box in normalized coords
    public let boundingBox: CGRect
    
    // All 1220 vertices
    public let vertices: [SIMD3<Float>]
    
    // Face anchor transform
    public let transform: simd_float4x4
    
    // Landmark count
    public let landmarkCount: Int
    
    init(anchor: ARFaceAnchor,
         viewportSize: CGSize) {
        
        let transform = anchor.transform
        
        // Extract angles from transform matrix
        self.yaw   = atan2(transform.columns.0.z,
                           transform.columns.2.z)
        self.pitch = asin(-transform.columns.1.z)
        self.roll  = atan2(transform.columns.1.x,
                           transform.columns.1.y)
        
        self.transform = transform
        
        // Get vertices from geometry
        let geometry = anchor.geometry
        let verts = geometry.vertices
        self.vertices = (0..<verts.count).map { verts[$0] }
        self.landmarkCount = verts.count
        
        // Eye positions from specific vertex indices
        // Left eye center ~= vertex 468
        // Right eye center ~= vertex 473
        self.leftEyePosition  = verts.count > 468 ? verts[468] : .zero
        self.rightEyePosition = verts.count > 473 ? verts[473] : .zero
        
        // Calculate bounding box from transform
        let facePos = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        
        // Approximate normalized bounding box
        // Face typically occupies center of frame
        self.boundingBox = CGRect(
            x: 0.2, y: 0.2,
            width: 0.6, height: 0.6
        )
    }
}
