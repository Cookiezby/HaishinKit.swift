import MetalKit
import UIKit



final class CutFaceFilter: PassThroughFilter {
    var outputTexture: MTLTexture
    
    init(device: MTLDevice) {
        outputTexture = MetalUtil.createEmptyTexture(device: device, width: 720, height: 1280)!
        super.init(device: device, label: "CutFace")
    }
    
    private func drawFace(commandBuffer: MTLCommandBuffer, faceRect: CGRect, inputTexture: MTLTexture, outputTexture: MTLTexture) {
        //出力用のTextureを設定する
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        guard let renderPipelineState = self.renderPipelineState else { return }
        let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

        let textureRect = faceRect.toFourPointRect2()
        //let textureRect = FourPointRect(leftTop: CGPoint(x: -0.5, y: 0.5), rightTop: CGPoint(x: 0.5, y: 0.5), leftBottom: CGPoint(x: -0.5, y: -0.5), rightBottom: CGPoint(x: 0.5, y: -0.5))
        let vertexes = createFaceVertex(textureRect: textureRect)
        //回転したTextureCoordsを獲得
        //let rotatedVertex = MetalUtil.rotateVertexInTextureCoords(vertexIn: vertexes, angle: faceInfo.rotation / 180.0 * CGFloat.pi, center: textureRect.center, rotateScale: 9.0 / 16.0)
        let vertexBuffer = device.makeBuffer(bytes: vertexes, length: MemoryLayout<VertexIn>.stride * vertexes.count, options: [])

        commandEncoder?.setRenderPipelineState(renderPipelineState)
        commandEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        commandEncoder?.setFragmentTexture(inputTexture, index: 0)
        commandEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        commandEncoder?.endEncoding()
    }
    
    func render(commandBuffer: MTLCommandBuffer, faceRect: CGRect, inputTexture: MTLTexture) {
        //faceInfoTextureList.append(FaceInfoTexture(faceInfo: faceInfoList[i], faceTexture: emptyTexture))
        drawFace(commandBuffer: commandBuffer, faceRect: faceRect, inputTexture: inputTexture, outputTexture: outputTexture)
    }
    //顔の正規化座標をて
    func createFaceVertex(textureRect: FourPointRect) -> [VertexIn] {
        let vertex: [VertexIn] = [
            VertexIn(position: SIMD4<Float>(-1,-1,0,1), textureCoordinate:  SIMD4<Float>(Float(textureRect.leftBottom.x),Float(1 - textureRect.leftBottom.y),0,1)),
            VertexIn(position:  SIMD4<Float>( 1,-1,0,1), textureCoordinate:  SIMD4<Float>(Float(textureRect.rightBottom.x),Float(1 - textureRect.rightBottom.y),0,1)),
            VertexIn(position:  SIMD4<Float>(-1, 1,0,1), textureCoordinate:  SIMD4<Float>(Float(textureRect.leftTop.x),Float(1 - textureRect.leftTop.y),0,1)),
            VertexIn(position:  SIMD4<Float>( 1, 1,0,1), textureCoordinate:  SIMD4<Float>(Float(textureRect.rightTop.x),Float(1 - textureRect.rightTop.y),0,1))
        ]
        return vertex
    }
}

