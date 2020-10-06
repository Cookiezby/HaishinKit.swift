//
//  PassThroughFilter.swift
//  TelePresence
//
//  Created by Bingyi Zhu on 2020/09/09.
//  Copyright © 2020 Bingyi Zhu. All rights reserved.
//

import Foundation
import MetalKit

class VertexInInputFilter {
    let device: MTLDevice
    let renderPassDescriptor: MTLRenderPassDescriptor
    var renderPipelineState: MTLRenderPipelineState? = nil
    let renderVertexDescriptor: MTLVertexDescriptor
    let renderPipelineStateDescriptor: MTLRenderPipelineDescriptor
    
    init(device: MTLDevice, label: String, vertexFunString: String, fragmentFunction: String) {
        self.device = device
        self.renderPassDescriptor = MTLRenderPassDescriptor()
        self.renderVertexDescriptor = VertexIn.vertexDescriptor
        
        let lib = device.makeDefaultLibrary()!
        let vertexFunction = lib.makeFunction(name: vertexFunString)!
        let fragmentFunction = lib.makeFunction(name: fragmentFunction)!
        
        renderPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineStateDescriptor.label = label
        renderPipelineStateDescriptor.vertexFunction   = vertexFunction
        renderPipelineStateDescriptor.fragmentFunction = fragmentFunction
        renderPipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderPipelineStateDescriptor.vertexDescriptor = renderVertexDescriptor
        
        do {
            self.renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineStateDescriptor)
        } catch {
            print("\(label) RenderPipelineState failed")
        }
    }
}

class PassThroughFilter: VertexInInputFilter {
    init(device: MTLDevice, label: String) {
        super.init(device: device, label: label, vertexFunString: "passThroughVertex", fragmentFunction: "passThroughFragment")
    }
}
