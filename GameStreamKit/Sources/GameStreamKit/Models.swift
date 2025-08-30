import Foundation
internal import Limelight

@objc public class StreamBufferEntry: NSObject {
    // Pointer to data (never NULL)
    // Size of data in bytes (never <= 0)
    @objc public let data: Data

    // Buffer type (only set for H.264 and HEVC formats)
    @objc public let bufferType: Int32

    @objc public init(data: Data, bufferType: Int32 = StreamBufferType.pictureData.rawValue) {
        self.data = data
        self.bufferType = bufferType
        super.init()
    }
}

// A decode unit describes a buffer chain of video data from multiple packets
@objc public class StreamDecodeUnit: NSObject {
    // Frame number
    @objc public let frameNumber: Int32

    // Frame type
    @objc public let frameType: Int32

    // Optional host processing latency of the frame, in 1/10 ms units.
    // Zero when the host doesn't provide the latency data
    // or frame processing latency is not applicable to the current frame
    // (happens when the frame is repeated).
    @objc public let frameHostProcessingLatency: UInt16

    // Receive time of first buffer. This value uses an implementation-defined epoch,
    // but the same epoch as enqueueTimeMs and LiGetMillis().
    @objc public let receiveTimeMs: UInt64

    // Time the frame was fully assembled and queued for the video decoder to process.
    // This is also approximately the same time as the final packet was received, so
    // enqueueTimeMs - receiveTimeMs is the time taken to receive the frame. At the
    // time the decode unit is passed to submitDecodeUnit(), the total queue delay
    // can be calculated by LiGetMillis() - enqueueTimeMs.
    @objc public let enqueueTimeMs: UInt64

    // Presentation time in microseconds with the epoch at the first captured frame.
    // This can be used to aid frame pacing or to drop old frames that were queued too
    // long prior to display.
    @objc public let presentationTimeUs: UInt64

    // Original RTP timestamp in 90kHz units. Useful when using APIs that deal with integer
    // time such as Apple's CMTime. To exactly recover the RTP timestamp, use something like
    // CMTimeMake((int64_t)du->rtpTimestamp, 90000);
    @objc public let rtpTimestamp: UInt32

    // Length of the entire buffer chain in bytes
    @objc public let fullLength: Int32

    // Head of the buffer chain (never NULL)
    @objc public let bufferList: [StreamBufferEntry]

    // Determines if this frame is SDR or HDR
    //
    // Note: This is not currently parsed from the actual bitstream, so if your
    // client has access to a bitstream parser, prefer that over this field.
    @objc public let isHdrActive: Bool

    // Provides the colorspace of this frame (see COLORSPACE_* defines above)
    //
    // Note: This is not currently parsed from the actual bitstream, so if your
    // client has access to a bitstream parser, prefer that over this field.
    @objc public let colorspace: UInt8

    @objc public init(frameNumber: Int32,
                frameType: Int32,
                frameHostProcessingLatency: UInt16 = 0,
                receiveTimeMs: UInt64,
                      enqueueTimeMs: UInt64,
                      presentationTimeUs: UInt64,
                      rtpTimestamp: UInt32,
                      bufferList: [StreamBufferEntry],
                      isHdrActive: Bool = false,
                      colorspace: UInt8 = 0) {
        self.frameNumber = frameNumber
        self.frameType = frameType
        self.frameHostProcessingLatency = frameHostProcessingLatency
        self.receiveTimeMs = receiveTimeMs
        self.enqueueTimeMs = enqueueTimeMs
        self.presentationTimeUs = presentationTimeUs
        self.rtpTimestamp = rtpTimestamp
        self.fullLength = bufferList.reduce(0) { $0 + Int32($1.data.count) }
        self.bufferList = bufferList
        self.isHdrActive = isHdrActive
        self.colorspace = colorspace
        super.init()
    }
    
    internal static func fromCStruct(_ cDecodeUnit: UnsafePointer<DECODE_UNIT>) -> StreamDecodeUnit {
        let du = cDecodeUnit.pointee
        var bufferEntries: [StreamBufferEntry] = []
        var currentEntry = du.bufferList
        while currentEntry != nil {
            let entry = currentEntry!.pointee
            let data = Data(bytes: entry.data, count: Int(entry.length))
            let bufferEntry = StreamBufferEntry(data: data, bufferType: entry.bufferType)
            bufferEntries.append(bufferEntry)
            currentEntry = entry.next
        }
        return StreamDecodeUnit(
            frameNumber: du.frameNumber,
            frameType: du.frameType,
            frameHostProcessingLatency: du.frameHostProcessingLatency,
            receiveTimeMs: du.receiveTimeMs,
            enqueueTimeMs: du.enqueueTimeMs,
            presentationTimeUs: du.presentationTimeUs,
            rtpTimestamp: du.rtpTimestamp,
            bufferList: bufferEntries,
            isHdrActive: du.hdrActive,
            colorspace: du.colorspace
        )
    }
}

@objc public final class VideoFrameHandle: NSObject {
    internal let rawHandle: UnsafeMutableRawPointer?
    internal init(rawHandle: UnsafeMutableRawPointer?) {
        self.rawHandle = rawHandle
        super.init()
    }
}
