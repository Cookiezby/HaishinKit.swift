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

struct FourPointRect {
    let leftTop: CGPoint
    let rightTop: CGPoint
    let leftBottom: CGPoint
    let rightBottom: CGPoint
}

extension CGRect {
    //Metal Vertex Coordinate
    func toVertexRect() -> FourPointRect {
        let vertexOriginX = (origin.x - 0.5) / 0.5
        let vertexOriginY = -(origin.y - 0.5) / 0.5
        let width = size.width * 2
        let height = size.height * 2
        
        let leftTop = CGPoint(x: vertexOriginX, y: vertexOriginY)
        let leftBottom = CGPoint(x: vertexOriginX, y: vertexOriginY - height)
        
        let rightTop = CGPoint(x: vertexOriginX + width, y: vertexOriginY)
        let rightBottom = CGPoint(x: vertexOriginX + width, y: vertexOriginY - height)
        return FourPointRect(leftTop: leftTop, rightTop: rightTop, leftBottom: leftBottom, rightBottom: rightBottom)
    }
    
    //Metal Texture Coordinate
    func toTextureRect() -> FourPointRect {
        let fourPoint = toFourPointRect2()
        let leftBottom = CGPoint(x: fourPoint.leftBottom.x * 2 - 1, y: fourPoint.leftBottom.y * 2 - 1)
        let rightBottom = CGPoint(x: fourPoint.rightBottom.x * 2 - 1, y: fourPoint.rightBottom.y * 2 - 1)
        let leftTop = CGPoint(x: fourPoint.leftTop.x * 2 - 1, y: fourPoint.leftTop.y * 2 - 1)
        let rightTop = CGPoint(x: fourPoint.rightTop.x * 2 - 1, y: fourPoint.rightTop.y * 2 - 1)
        return FourPointRect(leftTop: leftTop, rightTop: rightTop, leftBottom: leftBottom, rightBottom: rightBottom)
    }
    
    //iOS UI Coordinate
    func toFourPointRect() -> FourPointRect {
        let leftTop = CGPoint(x: origin.x, y: origin.y)
        let rightTop = CGPoint(x: origin.x + size.width, y: origin.y)
        let leftBottom = CGPoint(x: origin.x, y: origin.y + size.height)
        let rightBottom = CGPoint(x: origin.x + size.width, y: origin.y + size.height)
        return FourPointRect(leftTop: leftTop, rightTop: rightTop, leftBottom: leftBottom, rightBottom: rightBottom)
    }
    
    func toFourPointRect2() -> FourPointRect {
        let leftBottom = CGPoint(x: origin.x, y: origin.y)
        let rightBottom = CGPoint(x: origin.x + size.width, y: origin.y)
        let leftTop = CGPoint(x: origin.x, y: origin.y + size.height)
        let rightTop = CGPoint(x: origin.x + size.width, y: origin.y + size.height)
        return FourPointRect(leftTop: leftTop, rightTop: rightTop, leftBottom: leftBottom, rightBottom: rightBottom)
    }
    
    var center: CGPoint {
        return CGPoint(x: origin.x + width / 2, y: origin.y + height / 2)
    }
    
    func enlarge(top: CGFloat, left: CGFloat, right: CGFloat, bottom: CGFloat) -> CGRect {
        return self.inset(by: UIEdgeInsets(top: -top * height, left: -left * width, bottom: -bottom * height, right: -right * width))
    }
    
    //Rectを重なる部分を計算する
    static func calcRectOverlap(rect1: CGRect, rect2: CGRect) -> CGFloat {
        let leftTopX = max(rect1.origin.x, rect2.origin.x)
        let leftTopY = max(rect1.origin.y, rect2.origin.y)
        
        let rightBottomX = min(rect1.origin.x + rect1.size.width, rect2.origin.x + rect2.size.width)
        let rightBottomY = min(rect1.origin.y + rect1.size.height, rect2.origin.y + rect2.size.height)
        
        if leftTopX < rightBottomX && leftTopY < rightBottomY {
            return (rightBottomX - leftTopY) * (rightBottomY - leftTopY)
        } else {
            return 0
        }
    }
    
    //面積
    var area: CGFloat {
        return self.width * self.height
    }
}

extension Array where Element == Float {
    func metalBuffer(device: MTLDevice) -> MTLBuffer? {
        let size = self.count * MemoryLayout<Float>.size
        guard size > 0 else { return nil }
        return device.makeBuffer(bytes: self, length: size, options: MTLResourceOptions.storageModeShared)
    }
}

extension CGPoint {
    var vector: float4 {
        return float4(Float(x), Float(y), 0, 1)
    }
}

