import AVFoundation
import HaishinKit
import Photos
import UIKit
import VideoToolbox
import MetalKit

final class ExampleRecorderDelegate: DefaultAVRecorderDelegate {
    static let `default` = ExampleRecorderDelegate()

    override func didFinishWriting(_ recorder: AVRecorder) {
        guard let writer: AVAssetWriter = recorder.writer else {
            return
        }
        PHPhotoLibrary.shared().performChanges({() -> Void in
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: writer.outputURL)
        }, completionHandler: { _, error -> Void in
            do {
                try FileManager.default.removeItem(at: writer.outputURL)
            } catch {
                print(error)
            }
        })
    }
}

final class LiveViewController: UIViewController {
    private static let maxRetryCount: Int = 5

    @IBOutlet private weak var lfView: MTHKView!
    @IBOutlet private weak var currentFPSLabel: UILabel!
    @IBOutlet private weak var publishButton: UIButton!
    @IBOutlet private weak var pauseButton: UIButton!
    @IBOutlet private weak var videoBitrateLabel: UILabel!
    @IBOutlet private weak var videoBitrateSlider: UISlider!
    @IBOutlet private weak var audioBitrateLabel: UILabel!
    @IBOutlet private weak var zoomSlider: UISlider!
    @IBOutlet private weak var audioBitrateSlider: UISlider!
    @IBOutlet private weak var fpsControl: UISegmentedControl!
    @IBOutlet private weak var effectSegmentControl: UISegmentedControl!
    
    private var renderPipelineState: MTLRenderPipelineState?
    
    private lazy var metalView: MTKView = {
        let view = MTKView(frame: .zero, device: self.metalDevice)
        view.colorPixelFormat = .bgra8Unorm
        view.contentScaleFactor = UIScreen.main.scale
        view.delegate = self
        self.view.addSubview(view)
        return view
    }()

    private var rtmpConnection = RTMPConnection()
    private var rtmpStream: RTMPStream!
    private var sharedObject: RTMPSharedObject!
    private var currentEffect: VideoEffect?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var retryCount: Int = 0

    let metalDevice: MTLDevice = MTLCreateSystemDefaultDevice()!
    private let videoSize = CGSize(width: 360, height: 640)
    private lazy var compositionFilter: CompositionCameraFilter = {
        return CompositionCameraFilter(device: metalDevice, outputSize: videoSize)
    }()
    private lazy var cutFaceFilter: CutFaceFilter = {
        return CutFaceFilter(device: metalDevice)
    }()
    
    private lazy var testFilter: TestFilter = {
        return TestFilter(device: metalDevice, outputSize: videoSize)
    }()
    
    private lazy var commandQueue: MTLCommandQueue = {
        metalDevice.makeCommandQueue()!
    }()
    private var pixelBuffer: CVPixelBuffer?
    
    private lazy var textureCache: CVMetalTextureCache? = {
        var textureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, self.metalDevice, nil, &textureCache) != kCVReturnSuccess {
            fatalError("Unable to allocate texture cache")
        }
        return textureCache
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initRenderPipelineState()
        
        view.addSubview(metalView)
        metalView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        
        rtmpStream = RTMPStream(connection: rtmpConnection)
        rtmpStream.setMetalDevice(metalDevice: self.metalDevice)
        
        if let orientation = DeviceUtil.videoOrientation(by: UIApplication.shared.statusBarOrientation) {
            rtmpStream.orientation = orientation
        }
//        rtmpStream.captureSettings = [
//            .sessionPreset: AVCaptureSession.Preset.hd1280x720,
//            .continuousAutofocus: true,
//            .continuousExposure: true
//            .preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode.auto
//        ]
        
        rtmpStream.captureSettings = [
            .fps: 24
        ]
        
        rtmpStream.videoSettings = [
            .width: 720,
            .height: 1280
        ]
        rtmpStream.mixer.recorder.delegate = ExampleRecorderDelegate.shared

        videoBitrateSlider?.value = Float(RTMPStream.defaultVideoBitrate) / 1000
        audioBitrateSlider?.value = Float(RTMPStream.defaultAudioBitrate) / 1000

        NotificationCenter.default.addObserver(self, selector: #selector(on(_:)), name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        pixelBuffer = createPixelBuffer(width: Int(videoSize.width), height: Int(videoSize.height))
    }
    
    func initRenderPipelineState() {
        guard let library = metalDevice.makeDefaultLibrary() else { return }
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.sampleCount = 1
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .invalid
        
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "mapTexture")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "displayTexture")
        
        do {
            try renderPipelineState  = metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            assertionFailure("Failed creating a render state pipeline. Can't render the texture without one.")
            return
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        logger.info("viewWillAppear")
        super.viewWillAppear(animated)
        rtmpStream.attachAudio(AVCaptureDevice.default(for: .audio)) { error in
            logger.warn(error.description)
        }
//        rtmpStream.attachCamera(DeviceUtil.device(withPosition: currentPosition)) { error in
//            logger.warn(error.description)
//        }
        
        rtmpStream.addObserver(self, forKeyPath: "currentFPS", options: .new, context: nil)
        lfView?.attachStream(rtmpStream)
    }

    override func viewWillDisappear(_ animated: Bool) {
        logger.info("viewWillDisappear")
        super.viewWillDisappear(animated)
        rtmpStream.removeObserver(self, forKeyPath: "currentFPS")
        rtmpStream.close()
        rtmpStream.dispose()
    }

    @IBAction func rotateCamera(_ sender: UIButton) {
        logger.info("rotateCamera")
        let position: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        rtmpStream.captureSettings[.isVideoMirrored] = position == .front
//        rtmpStream.attachCamera(DeviceUtil.device(withPosition: position)) { error in
//            logger.warn(error.description)
//        }
        currentPosition = position
    }

    @IBAction func toggleTorch(_ sender: UIButton) {
        rtmpStream.torch.toggle()
    }

    @IBAction func on(slider: UISlider) {
        if slider == audioBitrateSlider {
            audioBitrateLabel?.text = "audio \(Int(slider.value))/kbps"
            rtmpStream.audioSettings[.bitrate] = slider.value * 1000
        }
        if slider == videoBitrateSlider {
            videoBitrateLabel?.text = "video \(Int(slider.value))/kbps"
            rtmpStream.videoSettings[.bitrate] = slider.value * 1000
        }
        if slider == zoomSlider {
            rtmpStream.setZoomFactor(CGFloat(slider.value), ramping: true, withRate: 5.0)
        }
    }
    
    func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
       var pixelBuffer: CVPixelBuffer?
       let status = CVPixelBufferCreate(nil, width, height,
                                        kCVPixelFormatType_32BGRA, nil,
                                        &pixelBuffer)
       if status != kCVReturnSuccess {
           print("Error: could not create resized pixel buffer", status)
           return nil
       }
       return pixelBuffer
   }

    @IBAction func on(pause: UIButton) {
        rtmpStream.paused.toggle()
    }

    @IBAction func on(close: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func on(publish: UIButton) {
        if publish.isSelected {
            UIApplication.shared.isIdleTimerDisabled = false
            rtmpConnection.close()
            rtmpConnection.removeEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
            rtmpConnection.removeEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
            publish.setTitle("●", for: [])
        } else {
            UIApplication.shared.isIdleTimerDisabled = true
            rtmpConnection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
            rtmpConnection.addEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
            rtmpConnection.connect(Preference.defaultInstance.uri!)
            publish.setTitle("■", for: [])
        }
        publish.isSelected.toggle()
    }

    @objc
    private func rtmpStatusHandler(_ notification: Notification) {
        let e = Event.from(notification)
        guard let data: ASObject = e.data as? ASObject, let code: String = data["code"] as? String else {
            return
        }
        logger.info(code)
        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            retryCount = 0
            rtmpStream!.publish(Preference.defaultInstance.streamName!)
            // sharedObject!.connect(rtmpConnection)
        case RTMPConnection.Code.connectFailed.rawValue, RTMPConnection.Code.connectClosed.rawValue:
            guard retryCount <= LiveViewController.maxRetryCount else {
                return
            }
            Thread.sleep(forTimeInterval: pow(2.0, Double(retryCount)))
            rtmpConnection.connect(Preference.defaultInstance.uri!)
            retryCount += 1
        default:
            break
        }
    }

    @objc
    private func rtmpErrorHandler(_ notification: Notification) {
        logger.error(notification)
        rtmpConnection.connect(Preference.defaultInstance.uri!)
    }

    func tapScreen(_ gesture: UIGestureRecognizer) {
        if let gestureView = gesture.view, gesture.state == .ended {
            let touchPoint: CGPoint = gesture.location(in: gestureView)
            let pointOfInterest = CGPoint(x: touchPoint.x / gestureView.bounds.size.width, y: touchPoint.y / gestureView.bounds.size.height)
            print("pointOfInterest: \(pointOfInterest)")
            rtmpStream.setPointOfInterest(pointOfInterest, exposure: pointOfInterest)
        }
    }

    @IBAction private func onFPSValueChanged(_ segment: UISegmentedControl) {
        switch segment.selectedSegmentIndex {
        case 0:
            rtmpStream.captureSettings[.fps] = 15.0
        case 1:
            rtmpStream.captureSettings[.fps] = 30.0
        case 2:
            rtmpStream.captureSettings[.fps] = 60.0
        default:
            break
        }
    }

    @IBAction private func onEffectValueChanged(_ segment: UISegmentedControl) {
        if let currentEffect: VideoEffect = currentEffect {
            _ = rtmpStream.unregisterVideoEffect(currentEffect)
        }
        switch segment.selectedSegmentIndex {
        case 1:
            currentEffect = MonochromeEffect()
            _ = rtmpStream.registerVideoEffect(currentEffect!)
        case 2:
            currentEffect = PronamaEffect()
            _ = rtmpStream.registerVideoEffect(currentEffect!)
        default:
            break
        }
    }

    @objc
    private func on(_ notification: Notification) {
        guard let orientation = DeviceUtil.videoOrientation(by: UIApplication.shared.statusBarOrientation) else {
            return
        }
        rtmpStream.orientation = orientation
    }

    @objc
    private func didEnterBackground(_ notification: Notification) {
        // rtmpStream.receiveVideo = false
    }

    @objc
    private func didBecomeActive(_ notification: Notification) {
        // rtmpStream.receiveVideo = true
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if Thread.isMainThread {
            currentFPSLabel?.text = "\(rtmpStream.currentFPS)"
        }
    }
}

extension LiveViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let frontSampleBuffer = rtmpStream.frontCameraSampleBuffer else { return }
        guard let frontTexture = sampleBufferToTexture(sampleBuffer: frontSampleBuffer) else { return }
        guard let backSampleBuffer = rtmpStream.backCameraSampleBuffer else { return }
        guard let backTexture = sampleBufferToTexture(sampleBuffer: backSampleBuffer) else { return }
        compositionFilter.render(commandBuffer: commandBuffer, backgroundTexture: backTexture, foregroundTexture: frontTexture)
        commandBuffer.commit()
      
        if let emptyPixelBuffer = createPixelBuffer(width: Int(videoSize.width), height: Int(videoSize.height)),
           let pixelBuffer = compositionFilter.outputTexture.toPixelBuffer(pixelBuffer: emptyPixelBuffer) {
            rtmpStream.updateSessionLastPixelBuffer(pixelBuffer)
        }
    }
    
    private func sampleBufferToTexture(sampleBuffer: CMSampleBuffer) -> MTLTexture? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        guard let textureCache = self.textureCache else { return nil }
        return createMetalTextureFromPixelBuffer(pixelBuffer, textureCache: textureCache)
    }
    
    private func render(texture: MTLTexture, withCommandBuffer commandBuffer: MTLCommandBuffer, device: MTLDevice) {
        guard let currentRenderPassDescriptor = metalView.currentRenderPassDescriptor,
              let currentDrawable = metalView.currentDrawable,
              let renderPipelineState = renderPipelineState,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: currentRenderPassDescriptor) else {
            return
        }
        
        encoder.setRenderPipelineState(renderPipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
        encoder.endEncoding()
        
        commandBuffer.addScheduledHandler { _ in }
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
    
    
    private func createMetalTextureFromPixelBuffer(_ pixelBuffer: CVPixelBuffer, textureCache: CVMetalTextureCache) -> MTLTexture? {
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTextureOut)
        guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
            print("failed to create metal texture")
            return nil
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        return texture
    }
}


extension CMSampleBuffer {
  static func make(from pixelBuffer: CVPixelBuffer, formatDescription: CMFormatDescription, timingInfo: inout CMSampleTimingInfo) -> CMSampleBuffer? {
    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil,
                                       refcon: nil, formatDescription: formatDescription, sampleTiming: &timingInfo, sampleBufferOut: &sampleBuffer)
    return sampleBuffer
  }
}

extension CMFormatDescription {
  static func make(from pixelBuffer: CVPixelBuffer) -> CMFormatDescription? {
    var formatDescription: CMFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
    return formatDescription
  }
}
