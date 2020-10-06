//
//  VertexIn.swift
//  TelePresence
//
//  Created by Bingyi Zhu on 2020/09/09.
//  Copyright © 2020 Bingyi Zhu. All rights reserved.
//

import Foundation
import MetalKit

struct VertexIn {
    var position: SIMD4<Float>
    var textureCoordinate: SIMD4<Float>
    static let normalized: [VertexIn] = [
        VertexIn(position: SIMD4<Float>(-1,-1,0,1), textureCoordinate: SIMD4<Float>(0,0,0,1)),
        VertexIn(position: SIMD4<Float>( 1,-1,0,1), textureCoordinate: SIMD4<Float>(1,0,0,1)),
        VertexIn(position: SIMD4<Float>(-1, 1,0,1), textureCoordinate: SIMD4<Float>(0,1,0,1)),
        VertexIn(position: SIMD4<Float>( 1, 1,0,1), textureCoordinate: SIMD4<Float>(1,1,0,1))
    ]
    
    static let textureVerticalFlipNormalized: [VertexIn] = [
        VertexIn(position: SIMD4<Float>(-1,-1,0,1), textureCoordinate: SIMD4<Float>(0,1,0,1)),
        VertexIn(position: SIMD4<Float>( 1,-1,0,1), textureCoordinate: SIMD4<Float>(1,1,0,1)),
        VertexIn(position: SIMD4<Float>(-1, 1,0,1), textureCoordinate: SIMD4<Float>(0,0,0,1)),
        VertexIn(position: SIMD4<Float>( 1, 1,0,1), textureCoordinate: SIMD4<Float>(1,0,0,1))
    ]
    
    static let textureHorizontalFlipNormalized: [VertexIn] = [
        VertexIn(position: SIMD4<Float>(-1,-1,0,1), textureCoordinate: SIMD4<Float>(1,1,0,1)),
        VertexIn(position: SIMD4<Float>( 1,-1,0,1), textureCoordinate: SIMD4<Float>(0,1,0,1)),
        VertexIn(position: SIMD4<Float>(-1, 1,0,1), textureCoordinate: SIMD4<Float>(1,0,0,1)),
        VertexIn(position: SIMD4<Float>( 1, 1,0,1), textureCoordinate: SIMD4<Float>(0,0,0,1))
    ]
    
    static let center: [VertexIn] = [
        VertexIn(position: SIMD4<Float>(-0.5,-0.5,0,1), textureCoordinate: SIMD4<Float>(0,1,0,1)),
        VertexIn(position: SIMD4<Float>( 0.5,-0.5,0,1), textureCoordinate: SIMD4<Float>(1,1,0,1)),
        VertexIn(position: SIMD4<Float>(-0.5, 0.5,0,1), textureCoordinate: SIMD4<Float>(0,0,0,1)),
        VertexIn(position: SIMD4<Float>( 0.5, 0.5,0,1), textureCoordinate: SIMD4<Float>(1,0,0,1))
    ]
    
    static let rightDownCorner: [VertexIn] = [
        VertexIn(position: SIMD4<Float>(0,-1,0,1), textureCoordinate: SIMD4<Float>(0,1,0,1)),
        VertexIn(position: SIMD4<Float>(1,-1,0,1), textureCoordinate: SIMD4<Float>(1,1,0,1)),
        VertexIn(position: SIMD4<Float>(0,0,0,1), textureCoordinate: SIMD4<Float>(0,0,0,1)),
        VertexIn(position: SIMD4<Float>(1,0,0,1), textureCoordinate: SIMD4<Float>(1,0,0,1))
    ]
    
    static let vertexDescriptor: MTLVertexDescriptor = {
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<VertexIn>.stride
        return vertexDescriptor
    }()
}
