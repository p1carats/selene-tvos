import Foundation
internal import Limelight

// Values for the 'streamingRemotely' field below
@objc public enum StreamMode: Int32 {
    case local = 0
    case remote = 1
    case auto = 2
}

// Values for the 'colorSpace' field below.
// Rec. 2020 is not supported with H.264 video streams on GFE hosts.
@objc public enum ColorSpace: Int32 {
    case rec601 = 0
    case rec709 = 1
    case rec2020 = 2
}

// Values for the 'colorRange' field below
@objc public enum ColorRange: Int32 {
    case limited = 0
    case full = 1
}

// Values for 'encryptionFlags' field below
@objc public class EncryptionFlags: NSObject {
    @objc public static let none = Int32(0x0000_0000)
    @objc public static let audio = Int32(0x0000_0001)
    @objc public static let video = Int32(0x0000_0002)
    @objc public static let all = Int32(bitPattern: 0xFFFF_FFFF)
}

@objc public class GameStreamConfiguration: NSObject {
    // Dimensions in pixels of the desired video stream
    @objc public var width: Int32
    @objc public var height: Int32

    // FPS of the desired video stream
    @objc public var fps: Int32

    // Bitrate of the desired video stream (audio adds another ~1 Mbps). This
    // includes error correction data, so the actual encoder bitrate will be
    // about 20% lower when using the standard 20% FEC configuration.
    @objc public var bitrate: Int32

    // Max video packet size in bytes (use 1024 if unsure). If STREAM_CFG_AUTO
    // determines the stream is remote (see below), it will cap this value at
    // 1024 to avoid MTU-related issues like packet loss and fragmentation.
    @objc public var packetSize: Int32

    // Determines whether to enable remote (over the Internet)
    // streaming optimizations. If unsure, set to STREAM_CFG_AUTO.
    // STREAM_CFG_AUTO uses a heuristic (whether the target address is
    // in the RFC 1918 address blocks) to decide whether the stream
    // is remote or not.
    @objc public var streamingRemotely: StreamMode

    // Specifies the channel configuration of the audio stream.
    // See AUDIO_CONFIGURATION constants and MAKE_AUDIO_CONFIGURATION() below.
    @objc public var audioConfiguration: Int32

    // Specifies the mask of supported video formats.
    // See VIDEO_FORMAT constants below.
    @objc public var supportedVideoFormats: Int32

    // If specified, the client's display refresh rate x 100. For example,
    // 59.94 Hz would be specified as 5994. This is used by recent versions
    // of GFE for enhanced frame pacing.
    @objc public var clientRefreshRateX100: Int32

    // If specified, sets the encoder colorspace to the provided COLORSPACE_*
    // option (listed above). If not set, the encoder will default to Rec 601.
    @objc public var colorSpace: ColorSpace

    // If specified, sets the encoder color range to the provided COLOR_RANGE_*
    // option (listed above). If not set, the encoder will default to Limited.
    @objc public var colorRange: ColorRange

    // Specifies the data streams where encryption may be enabled if supported
    // by the host PC. Ideally, you would pass ENCFLG_ALL to encrypt everything
    // that we support encrypting. However, lower performance hardware may not
    // be able to support encrypting heavy stuff like video or audio data, so
    // that encryption may be disabled here. Remote input encryption is always
    // enabled.
    @objc public var encryptionFlags: Int32

    // AES encryption data for the remote input stream. This must be
    // the same as what was passed as rikey and rikeyid
    // in /launch and /resume requests.
    @objc public var remoteInputAesKey: Data
    @objc public var remoteInputAesIv: Data

    @objc public override init() {
        self.width = 1920
        self.height = 1080
        self.fps = 60
        self.bitrate = 10000
        self.packetSize = 1024
        self.streamingRemotely = .auto
        self.audioConfiguration = StreamAudioConfiguration.stereo
        self.supportedVideoFormats = StreamVideoFormat.h264
        self.clientRefreshRateX100 = 6000
        self.colorSpace = .rec709
        self.colorRange = .limited
        self.encryptionFlags = EncryptionFlags.all
        self.remoteInputAesKey = Data(count: 16)
        self.remoteInputAesIv = Data(count: 16)
        super.init()
    }

    // Use this function to zero the stream configuration when allocated on the stack or heap
    @objc public func initializeFromDefaults() {
        var config = STREAM_CONFIGURATION()
        LiInitializeStreamConfiguration(&config)
        self.width = config.width
        self.height = config.height
        self.fps = config.fps
        self.bitrate = config.bitrate
        self.packetSize = config.packetSize
        self.streamingRemotely = StreamMode(rawValue: config.streamingRemotely) ?? .auto
        self.audioConfiguration = config.audioConfiguration
        self.supportedVideoFormats = config.supportedVideoFormats
        self.clientRefreshRateX100 = config.clientRefreshRateX100
        self.colorSpace = ColorSpace(rawValue: config.colorSpace) ?? .rec709
        self.colorRange = ColorRange(rawValue: config.colorRange) ?? .limited
        self.encryptionFlags = config.encryptionFlags
        self.remoteInputAesKey = withUnsafeBytes(of: config.remoteInputAesKey) { Data(bytes: $0.baseAddress!, count: 16) }
        self.remoteInputAesIv = withUnsafeBytes(of: config.remoteInputAesIv) { Data(bytes: $0.baseAddress!, count: 16) }
    }

    internal func toCStruct() -> STREAM_CONFIGURATION {
        var config = STREAM_CONFIGURATION()
        LiInitializeStreamConfiguration(&config)
        config.width = width
        config.height = height
        config.fps = fps
        config.bitrate = bitrate
        config.packetSize = packetSize
        config.streamingRemotely = streamingRemotely.rawValue
        config.audioConfiguration = audioConfiguration
        config.supportedVideoFormats = supportedVideoFormats
        config.clientRefreshRateX100 = clientRefreshRateX100
        config.colorSpace = colorSpace.rawValue
        config.colorRange = colorRange.rawValue
        config.encryptionFlags = encryptionFlags
        remoteInputAesKey.withUnsafeBytes { keyBytes in
            guard let base = keyBytes.baseAddress else { return }
            withUnsafeMutableBytes(of: &config.remoteInputAesKey) { dst in
                dst.copyMemory(from: UnsafeRawBufferPointer(start: base, count: min(keyBytes.count, 16)))
            }
        }
        remoteInputAesIv.withUnsafeBytes { ivBytes in
            guard let base = ivBytes.baseAddress else { return }
            withUnsafeMutableBytes(of: &config.remoteInputAesIv) { dst in
                dst.copyMemory(from: UnsafeRawBufferPointer(start: base, count: min(ivBytes.count, 16)))
            }
        }
        return config
    }
}
