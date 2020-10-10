import AVFoundation

#if os(iOS) || os(macOS)
    extension AVCaptureSession.Preset {
        static var `default`: AVCaptureSession.Preset = .medium
    }
#endif

protocol AVMixerDelegate: class {
    func didOutputAudio(_ buffer: AVAudioPCMBuffer, presentationTimeStamp: CMTime)
    func didOutputVideo(_ buffer: CMSampleBuffer)
}

@available(iOSApplicationExtension 13.0, *)
public class AVMixer {
    public static let bufferEmpty: Notification.Name = .init("AVMixerBufferEmpty")

    public static let defaultFPS: Float64 = 30
    public static let defaultVideoSettings: [NSString: AnyObject] = [
        kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_32BGRA)
    ]

    #if os(iOS) || os(macOS)
    public enum Option: String, KeyPathRepresentable, CaseIterable {
        case fps
        case isVideoMirrored
        case continuousAutofocus
        case continuousExposure

        #if os(iOS)
        case preferredVideoStabilizationMode
        #endif

        public var keyPath: AnyKeyPath {
            switch self {
            case .fps:
                return \AVMixer.fps
            case .continuousAutofocus:
                return \AVMixer.continuousAutofocus
            case .continuousExposure:
                return \AVMixer.continuousExposure
            case .isVideoMirrored:
                return \AVMixer.isVideoMirrored
            #if os(iOS)
            case .preferredVideoStabilizationMode:
                return \AVMixer.preferredVideoStabilizationMode
            #endif
            }
        }
    }
    #else
    public struct Option: KeyPathRepresentable {
        public static var allCases: [AVMixer.Option] = []
        public var keyPath: AnyKeyPath
        // swiftlint:disable nesting
        public typealias AllCases = [Option]
    }
    #endif

    #if os(iOS)
    var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode {
        get { videoIO.preferredVideoStabilizationMode }
        set { videoIO.preferredVideoStabilizationMode = newValue }
    }
    #endif

    #if os(iOS) || os(macOS)
    var fps: Float64 {
        get { videoIO.fps }
        set { videoIO.fps = newValue }
    }

    var isVideoMirrored: Bool {
        get { videoIO.isVideoMirrored }
        set { videoIO.isVideoMirrored = newValue }
    }

    var continuousExposure: Bool {
        get { videoIO.continuousExposure }
        set { videoIO.continuousExposure = newValue }
    }

    var continuousAutofocus: Bool {
        get { videoIO.continuousAutofocus }
        set { videoIO.continuousAutofocus = newValue }
    }

    private var _session: AVCaptureSession?
    public var session: AVCaptureSession {
        get {
            if _session == nil {
                _session = AVCaptureSession()
                _session?.sessionPreset = .default
            }
            return _session!
        }
        set {
            _session = newValue
        }
    }
    
    private var _multiCameraSession: AVCaptureMultiCamSession?
    public var multiCameraSession: AVCaptureMultiCamSession {
        get {
            if _multiCameraSession == nil {
                _multiCameraSession = AVCaptureMultiCamSession()
            }
            return _multiCameraSession!
        }
    }
    
    #endif

    var settings: Setting<AVMixer, Option> = [:] {
        didSet {
            settings.observer = self
        }
    }

    weak var delegate: AVMixerDelegate?

    private var _recorder: AVRecorder?
    /// The recorder instance.
    public var recorder: AVRecorder! {
        if _recorder == nil {
            _recorder = AVRecorder()
        }
        return _recorder
    }

    private var _audioIO: AudioIOComponent?
    var audioIO: AudioIOComponent! {
        if _audioIO == nil {
            _audioIO = AudioIOComponent(mixer: self)
        }
        return _audioIO!
    }

    private var _videoIO: MultiVideoIOComponent?
    var videoIO: MultiVideoIOComponent! {
        if _videoIO == nil {
            _videoIO = MultiVideoIOComponent(mixer: self)
        }
        return _videoIO!
    }

    deinit {
        dispose()
    }

    public init() {
        settings.observer = self
    }

    public func dispose() {
#if os(iOS) || os(macOS)
        if let session = _session, session.isRunning {
            session.stopRunning()
        }
#endif
        _audioIO?.dispose()
        _audioIO = nil
        _videoIO?.dispose()
        _videoIO = nil
    }

    func didBufferEmpty(_ component: IOComponent) {
        NotificationCenter.default.post(.init(name: AVMixer.bufferEmpty))
    }
}

extension AVMixer {
    public func startEncoding(delegate: Any) {
        videoIO.encoder.delegate = delegate as? VideoEncoderDelegate
        videoIO.encoder.startRunning()
        audioIO.encoder.delegate = delegate as? AudioConverterDelegate
        audioIO.encoder.startRunning()
    }

    public func stopEncoding() {
        videoIO.encoder.delegate = nil
        videoIO.encoder.stopRunning()
        audioIO.encoder.delegate = nil
        audioIO.encoder.stopRunning()
    }
}

extension AVMixer {
    public func startDecoding(_ audioEngine: AVAudioEngine?) {
        audioIO.startDecoding(audioEngine)
        videoIO.startDecoding()
    }

    public func stopDecoding() {
        audioIO.stopDecoding()
        videoIO.stopDecoding()
    }
}

#if os(iOS) || os(macOS)
extension AVMixer: Running {
    // MARK: Running
    public var isRunning: Atomic<Bool> {
        .init(multiCameraSession.isRunning)
    }

    public func startRunning() {
        guard !isRunning.value else {
            return
        }
        DispatchQueue.global(qos: .userInteractive).async {
            self.multiCameraSession.startRunning()
        }
    }

    public func stopRunning() {
        guard isRunning.value else {
            return
        }
        multiCameraSession.stopRunning()
    }
}
#else
extension AVMixer: Running {
    // MARK: Running
    public var isRunning: Atomic<Bool> {
        .init(false)
    }

    public func startRunning() {
    }

    public func stopRunning() {
    }
}
#endif
