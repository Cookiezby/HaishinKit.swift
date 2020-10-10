import AVFoundation
import CoreImage

public final class MultiVideoIOComponent: IOComponent {
    #if os(macOS)
    static let defaultAttributes: [NSString: NSObject] = [
        kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferOpenGLCompatibilityKey: kCFBooleanTrue
    ]
    #else
    static let defaultAttributes: [NSString: NSObject] = [
        kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferOpenGLESCompatibilityKey: kCFBooleanTrue
    ]
    #endif
    
    private let sessionQueue = DispatchQueue(label: "camera.multisession")
    private let dataOutputQueue = DispatchQueue(label: "camera.output")
    
    var metalDevice: MTLDevice!

    private lazy var textureCache: CVMetalTextureCache? = {
        var textureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, self.metalDevice, nil, &textureCache) != kCVReturnSuccess {
            fatalError("Unable to allocate texture cache")
        }
        return textureCache
    }()
    
    //MARK: Back Camera
    private var backCameraDeviceInput: AVCaptureDeviceInput?
    private var backCameraVideoDataOutput = AVCaptureVideoDataOutput()
    public var backCameraSampleBuffer: CMSampleBuffer?
    
    //MARK: Front Camera
    private var frontCameraDeviceInput: AVCaptureDeviceInput?
    private var frontCameraVideoDataOutput = AVCaptureVideoDataOutput()
    public var frontCameraSampleBuffer: CMSampleBuffer?
    
    public var lastPixelBuffer: CVPixelBuffer?
    
    let lockQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.VideoIOComponent.lock")

    var context: CIContext? {
        didSet {
            for effect in effects {
                effect.ciContext = context
            }
        }
    }

    #if os(iOS) || os(macOS)
    weak var renderer: NetStreamRenderer? = nil {
        didSet {
            renderer?.orientation = orientation
        }
    }
    #else
    weak var renderer: NetStreamRenderer?
    #endif

    var formatDescription: CMVideoFormatDescription? {
        didSet {
            decoder.formatDescription = formatDescription
        }
    }
    lazy var encoder = H264Encoder()
    lazy var decoder = H264Decoder()
    lazy var queue: DisplayLinkedQueue = {
        let queue = DisplayLinkedQueue()
        queue.delegate = self
        return queue
    }()

    private(set) var effects: Set<VideoEffect> = []

    private var extent = CGRect.zero {
        didSet {
            guard extent != oldValue else {
                return
            }
            pixelBufferPool = nil
        }
    }

    private var attributes: [NSString: NSObject] {
        var attributes: [NSString: NSObject] = MultiVideoIOComponent.defaultAttributes
        attributes[kCVPixelBufferWidthKey] = NSNumber(value: Int(extent.width))
        attributes[kCVPixelBufferHeightKey] = NSNumber(value: Int(extent.height))
        return attributes
    }

    private var _pixelBufferPool: CVPixelBufferPool?
    private var pixelBufferPool: CVPixelBufferPool! {
        get {
            if _pixelBufferPool == nil {
                var pixelBufferPool: CVPixelBufferPool?
                CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary?, &pixelBufferPool)
                _pixelBufferPool = pixelBufferPool
            }
            return _pixelBufferPool!
        }
        set {
            _pixelBufferPool = newValue
        }
    }

    #if os(iOS) || os(macOS)
    var fps: Float64 = AVMixer.defaultFPS {
        didSet {}
    }
    
    var position: AVCaptureDevice.Position = .back

    var videoSettings: [NSObject: AnyObject] = AVMixer.defaultVideoSettings {
        didSet {}
    }

    var isVideoMirrored = false {
        didSet {}
    }

    var orientation: AVCaptureVideoOrientation = .portrait

    var torch: Bool = false

    var continuousAutofocus: Bool = false
    var focusPointOfInterest: CGPoint?
    var exposurePointOfInterest: CGPoint?
    var continuousExposure: Bool = false

    #if os(iOS)
    var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode = .off
    #endif

    #endif

    #if os(iOS)
    var screen: CustomCaptureSession? = nil {
        didSet {
            if let oldValue: CustomCaptureSession = oldValue {
                oldValue.delegate = nil
            }
            if let screen: CustomCaptureSession = screen {
                screen.delegate = self
            }
        }
    }
    #endif

    override init(mixer: AVMixer) {
        super.init(mixer: mixer)
        encoder.lockQueue = lockQueue
        decoder.delegate = self
        
        guard configureBackCamera() else {
            print("configure back camera failed")
            return
        }
        
        guard configureFrontCamera() else {
            print("configure front camera failed")
            return
        }
    }

    #if os(iOS) || os(macOS)
    func attachCamera(_ camera: AVCaptureDevice?) throws {}


    func dispose() {
        if Thread.isMainThread {
            self.renderer?.attachStream(nil)
        } else {
            DispatchQueue.main.sync {
                self.renderer?.attachStream(nil)
            }
        }

        backCameraDeviceInput = nil
        frontCameraDeviceInput = nil
    }
    
    #else
    func dispose() {
        if Thread.isMainThread {
            self.renderer?.attachStream(nil)
        } else {
            DispatchQueue.main.sync {
                self.renderer?.attachStream(nil)
            }
        }
    }
    #endif

    @inline(__always)
    func effect(_ buffer: CVImageBuffer, info: CMSampleBuffer?) -> CIImage {
        var image = CIImage(cvPixelBuffer: buffer)
        for effect in effects {
            image = effect.execute(image, info: info)
        }
        return image
    }

    func registerEffect(_ effect: VideoEffect) -> Bool {
        effect.ciContext = context
        return effects.insert(effect).inserted
    }

    func unregisterEffect(_ effect: VideoEffect) -> Bool {
        effect.ciContext = nil
        return effects.remove(effect) != nil
    }
}

extension MultiVideoIOComponent {
    func encodeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let buffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        var imageBuffer: CVImageBuffer?

        CVPixelBufferLockBaseAddress(buffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            if let imageBuffer = imageBuffer {
                CVPixelBufferUnlockBaseAddress(imageBuffer, [])
            }
        }

        if renderer != nil || !effects.isEmpty {
            let image: CIImage = effect(buffer, info: sampleBuffer)
            extent = image.extent
            if !effects.isEmpty {
                #if os(macOS)
                CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &imageBuffer)
                #else
                if buffer.width != Int(extent.width) || buffer.height != Int(extent.height) {
                    CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &imageBuffer)
                }
                #endif
                if let imageBuffer = imageBuffer {
                    CVPixelBufferLockBaseAddress(imageBuffer, [])
                }
                context?.render(image, to: imageBuffer ?? buffer)
            }
            renderer?.render(image: image)
        }

        encoder.encodeImageBuffer(
            buffer,
            presentationTimeStamp: sampleBuffer.presentationTimeStamp,
            duration: sampleBuffer.duration
        )

        mixer?.recorder.appendPixelBuffer(imageBuffer ?? buffer, withPresentationTime: sampleBuffer.presentationTimeStamp)
    }
}

extension MultiVideoIOComponent {
    func startDecoding() {
        queue.startRunning()
        decoder.startRunning()
    }

    func stopDecoding() {
        decoder.stopRunning()
        queue.stopRunning()
        renderer?.render(image: nil)
    }

    func decodeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        _ = decoder.decodeSampleBuffer(sampleBuffer)
    }
}

extension MultiVideoIOComponent: AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    public func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let videoDataOutput = captureOutput as? AVCaptureVideoDataOutput else { return }
        if videoDataOutput == frontCameraVideoDataOutput {
            frontCameraSampleBuffer = sampleBuffer
            var timeInfo = CMSampleTimingInfo(duration: sampleBuffer.duration, presentationTimeStamp: sampleBuffer.presentationTimeStamp, decodeTimeStamp: sampleBuffer.decodeTimeStamp)
            if let lastPixelBuffer = lastPixelBuffer, let formatDescription = CMFormatDescription.make(from: lastPixelBuffer) {
                if let newSampleBuffer = CMSampleBuffer.make(from: lastPixelBuffer, formatDescription: formatDescription, timingInfo: &timeInfo) {
                    encodeSampleBuffer(newSampleBuffer)
                }
            }
        }
        
        if videoDataOutput == backCameraVideoDataOutput {
            backCameraSampleBuffer = sampleBuffer
        }
    }
}

extension MultiVideoIOComponent: VideoDecoderDelegate {
    // MARK: VideoDecoderDelegate
    func sampleOutput(video sampleBuffer: CMSampleBuffer) {
        queue.enqueue(sampleBuffer)
    }
}

extension MultiVideoIOComponent: DisplayLinkedQueueDelegate {
    // MARK: DisplayLinkedQueue
    func queue(_ buffer: CMSampleBuffer) {
        renderer?.render(image: CIImage(cvPixelBuffer: buffer.imageBuffer!))
        mixer?.delegate?.didOutputVideo(buffer)
    }

    func empty() {
        mixer?.didBufferEmpty(self)
    }
}

extension MultiVideoIOComponent {
    private func configureBackCamera() -> Bool {
        guard let session = mixer?.session else { return false }
        
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("could not find back camera")
            return false
        }
        
        do {
            backCameraDeviceInput = try AVCaptureDeviceInput(device: backCamera)
            
            guard let backCameraDeviceInput = backCameraDeviceInput, session.canAddInput(backCameraDeviceInput) else {
                print("could not add back camera device input")
                return false
            }
            
            session.addInput(backCameraDeviceInput)
        } catch {
            print("could not create back camera device input \(error)")
            return false
        }
        
        guard let backCameraDeviceInput = backCameraDeviceInput, let backCameraVideoPort = backCameraDeviceInput.ports(for: .video, sourceDeviceType: backCamera.deviceType, sourceDevicePosition: backCamera.position).first else {
            print("could not find the back camera device input's video port")
            return false
        }
        
        guard session.canAddOutput(backCameraVideoDataOutput) else {
            print("could not add the back camera video data output")
            return false
        }
        
        session.addOutputWithNoConnections(backCameraVideoDataOutput)
        backCameraVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        backCameraVideoDataOutput.alwaysDiscardsLateVideoFrames = true
        backCameraVideoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        
        let backCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [backCameraVideoPort], output: backCameraVideoDataOutput)
        
        guard session.canAddConnection(backCameraVideoDataOutputConnection) else {
            print("could not add a connection to the back camera video data output")
            return false
        }
        
        session.addConnection(backCameraVideoDataOutputConnection)
        backCameraVideoDataOutputConnection.videoOrientation = .portrait
        return true
    }
    
    func configureFrontCamera() -> Bool {
        guard let session = mixer?.session else { return false }
        
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }
        
        // Find the front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Could not find the front camera")
            return false
        }
        
        // Add the front camera input to the session
        do {
            frontCameraDeviceInput = try AVCaptureDeviceInput(device: frontCamera)
            
            guard let frontCameraDeviceInput = frontCameraDeviceInput,
                session.canAddInput(frontCameraDeviceInput) else {
                    print("Could not add front camera device input")
                    return false
            }
            session.addInputWithNoConnections(frontCameraDeviceInput)
        } catch {
            print("Could not create front camera device input: \(error)")
            return false
        }
        
        // Find the front camera device input's video port
        guard let frontCameraDeviceInput = frontCameraDeviceInput,
            let frontCameraVideoPort = frontCameraDeviceInput.ports(for: .video,
                                                                    sourceDeviceType: frontCamera.deviceType,
                                                                    sourceDevicePosition: frontCamera.position).first else {
                                                                        print("Could not find the front camera device input's video port")
                                                                        return false
        }
        
        // Add the front camera video data output
        guard session.canAddOutput(frontCameraVideoDataOutput) else {
            print("Could not add the front camera video data output")
            return false
        }
        session.addOutputWithNoConnections(frontCameraVideoDataOutput)
        frontCameraVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        frontCameraVideoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        frontCameraVideoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        // Connect the front camera device input to the front camera video data output
        let frontCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [frontCameraVideoPort], output: frontCameraVideoDataOutput)
        guard session.canAddConnection(frontCameraVideoDataOutputConnection) else {
            print("Could not add a connection to the front camera video data output")
            return false
        }
        session.addConnection(frontCameraVideoDataOutputConnection)
        frontCameraVideoDataOutputConnection.videoOrientation = .portrait
        frontCameraVideoDataOutputConnection.automaticallyAdjustsVideoMirroring = false
        frontCameraVideoDataOutputConnection.isVideoMirrored = true
        return true
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
