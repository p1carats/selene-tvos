import Foundation

// These identify codec configuration data in the buffer lists
// of frames identified as IDR frames for H.264 and HEVC formats.
// For other codecs, all data is marked as BUFFER_TYPE_PICDATA.
@objc public enum StreamBufferType: Int32 {
    case pictureData = 0
    case sps = 1
    case pps = 2
    case vps = 3
}

@objc public enum StreamFrameType: Int32 {
    // This is a standard frame which references the IDR frame and
    // previous P-frames.
    case pFrame = 0

    // This is a key frame.
    //
    // For H.264 and HEVC, this means the frame contains SPS, PPS, and VPS (HEVC only) NALUs
    // as the first buffers in the list. The I-frame data follows immediately
    // after the codec configuration NALUs.
    //
    // For other codecs, any configuration data is not split into separate buffers.
    case idrFrame = 1
}

// Passed in StreamConfiguration.supportedVideoFormats to specify supported codecs
// and to DecoderRendererSetup() to specify selected codec.
@objc public class StreamVideoFormat: NSObject {
    @objc public static let h264 = Int32(0x0001) // H.264 High Profile
    @objc public static let h264High8_444 = Int32(0x0004) // H.264 High 8-bit 4:4:4
    @objc public static let h265 = Int32(0x0100) // HEVC Main Profile
    @objc public static let h265Main10 = Int32(0x0200) // HEVC Main10 Profile
    @objc public static let h265Rext8_444 = Int32(0x0400) // HEVC RExt 4:4:4 8-bit Profile
    @objc public static let h265Rext10_444 = Int32(0x0800) // HEVC RExt 4:4:4 10-bit Profile
    @objc public static let av1Main8 = Int32(0x1000) // AV1 Main 8-bit profile
    @objc public static let av1Main10 = Int32(0x2000) // AV1 Main 10-bit profile
    @objc public static let av1High8_444 = Int32(0x4000) // AV1 High 4:4:4 8-bit profile
    @objc public static let av1High10_444 = Int32(0x8000) // AV1 High 4:4:4 10-bit profile

    // Masks for clients to use to match video codecs without profile-specific details.
    @objc public static let maskH264 = Int32(0x000F)
    @objc public static let maskH265 = Int32(0x0F00)
    @objc public static let maskAv1 = Int32(0xF000)
    @objc public static let mask10Bit = Int32(0xAA00)
    @objc public static let maskYuv444 = Int32(0xCC04)
}

@objc public class RendererCapabilities: NSObject {
    // If set in the renderer capabilities field, this flag will cause audio/video data to
    // be submitted directly from the receive thread. This should only be specified if the
    // renderer is non-blocking. This flag is valid on both audio and video renderers.
    @objc public static let directSubmit = Int32(0x1)

    // If set in the video renderer capabilities field, this flag specifies that the renderer
    // supports reference frame invalidation for AVC/H.264 streams. This flag is only valid on video renderers.
    // If using this feature, the bitstream may not be patched (changing num_ref_frames or max_dec_frame_buffering)
    // to avoid video corruption on packet loss.
    @objc public static let referenceFrameInvalidationAvc = Int32(0x2)

    // If set in the video renderer capabilities field, this flag specifies that the renderer
    // supports reference frame invalidation for HEVC/H.265 streams. This flag is only valid on video renderers.
    @objc public static let referenceFrameInvalidationHevc = Int32(0x4)

    // If set in the audio renderer capabilities field, this flag will cause the RTSP negotiation
    // to never request the "high quality" audio preset. If unset, high quality audio will be
    // used with video streams above 15 Mbps.
    @objc public static let slowOpusDecoder = Int32(0x8)

    // If set in the audio renderer capabilities field, this indicates that audio packets
    // may contain more or less than 5 ms of audio. This requires that audio renderers read the
    // samplesPerFrame field in OPUS_MULTISTREAM_CONFIGURATION to calculate the correct decoded
    // buffer size rather than just assuming it will always be 240.
    @objc public static let supportsArbitraryAudioDuration = Int32(0x10)

    // This flag opts the renderer into a pull-based model rather than the default push-based
    // callback model. The renderer must invoke the new functions (LiWaitForNextVideoFrame(),
    // LiCompleteVideoFrame(), and similar) to receive A/V data. Setting this capability while
    // also providing a sample callback is not allowed.
    @objc public static let pullRenderer = Int32(0x20)

    // If set in the video renderer capabilities field, this flag specifies that the renderer
    // supports reference frame invalidation for AV1 streams. This flag is only valid on video renderers.
    @objc public static let referenceFrameInvalidationAv1 = Int32(0x40)

    // If set in the video renderer capabilities field, this macro specifies that the renderer
    // supports slicing to increase decoding performance. The parameter specifies the desired
    // number of slices per frame. This capability is only valid on video renderers.
    @objc public static func slicesPerFrame(_ slices: UInt8) -> UInt32 { UInt32(slices) << 24 }
}

@objc public enum DecoderRendererStatus: Int32 {
    case ok = 0
    case needIdr = -1
}

// Subject to change in future releases
// Use LiGetStageName() for stable stage names
@objc public enum StreamStage: Int32 {
    case none = 0
    case platformInit = 1
    case nameResolution = 2
    case audioStreamInit = 3
    case rtspHandshake = 4
    case controlStreamInit = 5
    case videoStreamInit = 6
    case inputStreamInit = 7
    case controlStreamStart = 8
    case videoStreamStart = 9
    case audioStreamStart = 10
    case inputStreamStart = 11
    case max = 12
}

@objc public enum StreamErrorCode: Int32 {
    // This error code is passed to ConnListenerConnectionTerminated() when the stream
    // is being gracefully terminated by the host. It usually means the app on the host
    // PC has exited.
    case gracefulTermination = 0

    // This error is passed to ConnListenerConnectionTerminated() if no video data
    // was ever received for this connection after waiting several seconds. It likely
    // indicates a problem with traffic on UDP 47998 due to missing or incorrect
    // firewall or port forwarding rules.
    case noVideoTraffic = -100

    // This error is passed to ConnListenerConnectionTerminated() if a fully formed
    // frame could not be received after waiting several seconds. It likely indicates
    // an extremely unstable connection or a bitrate that is far too high.
    case noVideoFrame = -101

    // This error is passed to ConnListenerConnectionTerminated() if the stream ends
    // very soon after starting due to a graceful termination from the host. Usually
    // this seems to happen if DRM protected content is on-screen (pre-GFE 3.22), or
    // another issue that prevents the encoder from being able to capture video successfully.
    case unexpectedEarlyTermination = -102

    // This error is passed to ConnListenerConnectionTerminated() if the stream ends
    // due to a protected content error from the host. This value is supported on GFE 3.22+.
    case protectedContent = -103

    // This error is passed to ConnListenerConnectionTerminated() if the stream ends
    // due a frame conversion error. This is most commonly due to an incompatible
    // desktop resolution and streaming resolution with HDR enabled. This value is
    // supported on GFE 3.22+.
    case frameConversion = -104

    // Error return value to indicate that the requested functionality is not supported by the host
    case unsupported = -5501
}

@objc public enum StreamConnectionStatus: Int32 {
    case okay = 0
    case poor = 1
}

@objc public class ServerCodecModeSupport: NSObject {
    // ServerCodecModeSupport values
    @objc public static let h264 = Int32(0x0000_0001)
    @objc public static let hevc = Int32(0x0000_0100)
    @objc public static let hevcMain10 = Int32(0x0000_0200)
    @objc public static let av1Main8 = Int32(0x0001_0000) // Sunshine extension
    @objc public static let av1Main10 = Int32(0x0002_0000) // Sunshine extension
    @objc public static let h264High8_444 = Int32(0x0004_0000) // Sunshine extension
    @objc public static let hevcRext8_444 = Int32(0x0008_0000) // Sunshine extension
    @objc public static let hevcRext10_444 = Int32(0x0010_0000) // Sunshine extension
    @objc public static let av1High8_444 = Int32(0x0020_0000) // Sunshine extension
    @objc public static let av1High10_444 = Int32(0x0040_0000) // Sunshine extension

    // SCM masks to identify various codec capabilities
    @objc public static let maskH264: Int32 = h264 | h264High8_444
    @objc public static let maskH265: Int32 = hevc | hevcMain10 | hevcRext8_444 | hevcRext10_444
    @objc public static let maskAv1: Int32 = av1Main8 | av1Main10 | av1High8_444 | av1High10_444
    @objc public static let mask10Bit: Int32 = hevcMain10 | av1Main10 | hevcRext10_444 | av1High10_444
    @objc public static let maskYuv444: Int32 = h264High8_444 | hevcRext8_444 | hevcRext10_444 | av1High8_444 | av1High10_444
}

@objc public class PortConstants: NSObject {
    // Port index flags for use with LiGetPortFromPortFlagIndex() and LiGetProtocolFromPortFlagIndex()
    @objc public static let indexTcp47984 = Int32(0)
    @objc public static let indexTcp47989 = Int32(1)
    @objc public static let indexTcp48010 = Int32(2)
    @objc public static let indexUdp47998 = Int32(8)
    @objc public static let indexUdp47999 = Int32(9)
    @objc public static let indexUdp48000 = Int32(10)
    @objc public static let indexUdp48010 = Int32(11)

    // Port flags for use with LiTestClientConnectivity()
    @objc public static let flagAll = UInt32(0xFFFFFFFF)
    @objc public static let flagTcp47984 = UInt32(0x0001)
    @objc public static let flagTcp47989 = UInt32(0x0002)
    @objc public static let flagTcp48010 = UInt32(0x0004)
    @objc public static let flagUdp47998 = UInt32(0x0100)
    @objc public static let flagUdp47999 = UInt32(0x0200)
    @objc public static let flagUdp48000 = UInt32(0x0400)
    @objc public static let flagUdp48010 = UInt32(0x0800)

    @objc public static let testResultInconclusive = UInt32(0xFFFFFFFF)
}
