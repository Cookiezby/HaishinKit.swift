//
//  MTLTexture+Extension.swift
//  TelePresence
//
//  Created by Bingyi Zhu on 2020/09/08.
//  Copyright © 2020 Bingyi Zhu. All rights reserved.
//

import Foundation
import MetalKit

extension MTLTexture {
    func threadGroupCount() -> MTLSize {
        return MTLSizeMake(8, 8, 1)
    }
    
    func threadGroups() -> MTLSize {
        let groupCount = threadGroupCount()
        return MTLSizeMake(Int(self.width) / groupCount.width, Int(self.height) / groupCount.height, 1)
    }
    
    func toPixelBuffer(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let emptyBufferBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        guard let noNilBaseAddress = baseAddress else { return nil }
        getBytes(noNilBaseAddress, bytesPerRow: emptyBufferBytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixelBuffer
    }
}

class MetalUtil {
    static func createEmptyTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        let texture = device.makeTexture(descriptor: textureDescriptor)
        return texture
    }
}
