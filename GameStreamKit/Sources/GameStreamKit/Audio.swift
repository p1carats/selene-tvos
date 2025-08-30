import Foundation
internal import Limelight

@objc public class StreamAudioConfiguration: NSObject {
    // Specifies that the audio stream should be encoded in stereo (default)
    @objc public static let stereo = makeConfiguration(channelCount: 2, channelMask: 0x3)

    // Specifies that the audio stream should be in 5.1 surround sound if the PC is able
    @objc public static let surround51 = makeConfiguration(channelCount: 6, channelMask: 0x3F)

    // Specifies that the audio stream should be in 7.1 surround sound if the PC is able
    @objc public static let surround71 = makeConfiguration(channelCount: 8, channelMask: 0x63F)

    // Specifies an audio configuration by channel count and channel mask
    // See https://docs.microsoft.com/en-us/windows-hardware/drivers/audio/channel-mask for channelMask values
    // NOTE: Not all combinations are supported by GFE and/or this library.
    @objc public static func makeConfiguration(channelCount: Int32, channelMask: Int32) -> Int32 {
        return ((channelMask << 16) | (channelCount << 8) | 0xCA)
    }

    // Helper macros for retreiving channel count and channel mask from the audio configuration
    @objc public static func channelCount(from configuration: Int32) -> Int32 {
        return (configuration >> 8) & 0xFF
    }
    @objc public static func channelMask(from configuration: Int32) -> Int32 {
        return (configuration >> 16) & 0xFFFF
    }

    // Helper macro to retreive the surroundAudioInfo parameter value that must be passed in
    // the /launch and /resume HTTPS requests when starting the session.
    @objc public static func surroundAudioInfo(from configuration: Int32) -> Int32 {
        return (channelMask(from: configuration) << 16) | channelCount(from: configuration)
    }

    // The maximum number of channels supported
    @objc public static let maxChannelCount = Int32(8)
}

// This structure provides the Opus multistream decoder parameters required to successfully
// decode the audio stream being sent from the computer. See opus_multistream_decoder_init docs
// for details about these fields.
//
// The supplied mapping array is indexed according to the following output channel order:
// 0 - Front Left
// 1 - Front Right
// 2 - Center
// 3 - LFE
// 4 - Back Left
// 5 - Back Right
// 6 - Side Left
// 7 - Side Right
//
// If the mapping order does not match the channel order of the audio renderer, you may swap
// the values in the mismatched indices until the mapping array matches the desired channel order.
@objc public class OpusMultistreamConfiguration: NSObject {
    @objc public let sampleRate: Int32
    @objc public let channelCount: Int32
    @objc public let streams: Int32
    @objc public let coupledStreams: Int32
    @objc public let samplesPerFrame: Int32
    @objc public let mapping: NSData

    @objc public init(sampleRate: Int32,
                channelCount: Int32,
                streams: Int32,
                      coupledStreams: Int32,
                      samplesPerFrame: Int32,
                      mapping: [UInt8]) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.streams = streams
        self.coupledStreams = coupledStreams
        self.samplesPerFrame = samplesPerFrame
        self.mapping = NSData(bytes: mapping, length: mapping.count)
        super.init()
    }

    internal static func fromCStruct(_ cConfig: OPUS_MULTISTREAM_CONFIGURATION) -> OpusMultistreamConfiguration {
        let mappingArray = withUnsafeBytes(of: cConfig.mapping) { bytes in
            Array(bytes.bindMemory(to: UInt8.self))
        }
        return OpusMultistreamConfiguration(
            sampleRate: cConfig.sampleRate,
            channelCount: cConfig.channelCount,
            streams: cConfig.streams,
            coupledStreams: cConfig.coupledStreams,
            samplesPerFrame: cConfig.samplesPerFrame,
            mapping: mappingArray
        )
    }
}
