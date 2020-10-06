//
//  CompositionFilter.swift
//  TelePresence
//
//  Created by Bingyi Zhu on 2020/10/01.
//  Copyright © 2020 Bingyi Zhu. All rights reserved.
//

import Foundation
import UIKit
import MetalKit

final class CompositionCameraFilter: PassThroughFilter {
    let outputTexture: MTLTexture
    
    init(device: MTLDevice, outputSize: CGSize) {
        self.outputTexture = MetalUtil.createEmptyTexture(device: device, width: Int(outputSize.width), height: Int(outputSize.height))!
        super.init(device: device, label: "CompositionCameraFilter")
    }
    
    func render(commandBuffer: MTLCommandBuffer, backgroundTexture: MTLTexture, foregroundTexture: MTLTexture) {
        guard let renderPipelineState = self.renderPipelineState else { return }
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        commandEncoder?.setRenderPipelineState(renderPipelineState)
        
        let backgroundVertexBuffer = device.makeBuffer(bytes: VertexIn.textureVerticalFlipNormalized, length: MemoryLayout<VertexIn>.stride * VertexIn.textureVerticalFlipNormalized.count, options: [])
        commandEncoder?.setVertexBuffer(backgroundVertexBuffer, offset: 0, index: 0)
        commandEncoder?.setFragmentTexture(backgroundTexture, index: 0)
        commandEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
       
        
        let foregroundVertexBuffer = device.makeBuffer(bytes: VertexIn.rightDownCorner, length: MemoryLayout<VertexIn>.stride * VertexIn.rightDownCorner.count, options: [])
        commandEncoder?.setVertexBuffer(foregroundVertexBuffer, offset: 0, index: 0)
        commandEncoder?.setFragmentTexture(foregroundTexture, index: 0)
        commandEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        commandEncoder?.endEncoding()
    }
}
