import Foundation
internal import Limelight

//
// This header exposes the public streaming API for client usage
//
@objc public class GameStream: NSObject {
    nonisolated(unsafe) internal static var connectionDelegate: ConnectionDelegate?
    nonisolated(unsafe) internal static var videoDecoderDelegate: VideoDecoderDelegate?
    nonisolated(unsafe) internal static var audioRendererDelegate: AudioRendererDelegate?

    // This function returns a string that you SHOULD append to the /launch and /resume
    // query parameter string. This is used to enable certain extended functionality
    // with Sunshine hosts. The returned string is owned by moonlight-common-c and
    // should not be freed by the caller.
    @objc public static func getLaunchUrlQueryParameters() -> String {
        LiGetLaunchUrlQueryParameters().map { String(cString: $0) } ?? ""
    }

    // Use to get a user-visible string to display initialization progress
    // from the integer passed to the ConnListenerStageXXX callbacks
    @objc public static func getStageName(for stage: Int32) -> String {
        LiGetStageName(stage).map { String(cString: $0) } ?? ""
    }

    // This function returns an estimate of the current RTT to the host PC obtained via ENet
    // protocol statistics. This function will fail if the current GFE version does not use
    // ENet for the control stream (very old versions), or if the ENet peer is not connected.
    // This function may only be called between LiStartConnection() and LiStopConnection().
    @objc public static func getEstimatedRttInfo(estimatedRtt: UnsafeMutablePointer<UInt32>, estimatedRttVariance: UnsafeMutablePointer<UInt32>) -> Bool {
        return LiGetEstimatedRttInfo(estimatedRtt, estimatedRttVariance)
    }

    // This function returns a time in milliseconds with an implementation-defined epoch.
    @objc public static func getMillis() -> UInt64 {
        return LiGetMillis()
    }
    
    // This is a simplistic STUN function that can assist clients in getting the WAN address
    // for machines they find using mDNS over IPv4. This can be used to pre-populate the external
    // address for streaming after GFE stopped sending it a while back. wanAddr is returned in
    // network byte order.
    @objc public static func findExternalAddressIPv4(stunServer: String, stunPort: UInt16, wanAddr: UnsafeMutablePointer<UInt32>) -> Int32 {
        return stunServer.withCString { LiFindExternalAddressIP4($0, stunPort, wanAddr) }
    }

    // Returns the number of queued video frames ready for delivery. Only relevant
    // if CAPABILITY_DIRECT_SUBMIT is not set for the video renderer.
    @objc public static func getPendingVideoFrames() -> Int32 {
        LiGetPendingVideoFrames()
    }

    // Returns the number of queued audio frames ready for delivery. Only relevant
    // if CAPABILITY_DIRECT_SUBMIT is not set for the audio renderer. For most uses,
    // LiGetPendingAudioDuration() is probably a better option than this function.
    @objc public static func getPendingAudioFrames() -> Int32 {
        LiGetPendingAudioFrames()
    }

    // Similar to LiGetPendingAudioFrames() except it returns the pending audio in
    // milliseconds rather than frames, which allows callers to be agnostic of th
    // negotiated audio frame duration.
    @objc public static func getPendingAudioDuration() -> Int32 {
        LiGetPendingAudioDuration()
    }

    // Returns the port flags that correspond to ports involved in a failing connection stage, or
    // connection termination error.
    //
    // These may be used to specifically test the ports that could have caused the connection failure.
    // If no ports are likely involved with a given failure, this function returns 0.
    @objc public static func getPortFlagsFromStage(_ stage: Int32) -> UInt32 {
        LiGetPortFlagsFromStage(stage)
    }
    @objc public static func getPortFlagsFromTerminationErrorCode(errorCode: Int32) -> UInt32 {
        LiGetPortFlagsFromTerminationErrorCode(errorCode)
    }

    // Returns the IPPROTO_* value for the specified port index 
    @objc public static func getProtocolFromPortFlagIndex(_ portFlagIndex: Int32) -> Int32 {
        LiGetProtocolFromPortFlagIndex(portFlagIndex)
    }

    // Returns the port number for the specified port index
    @objc public static func getPortFromPortFlagIndex(_ portFlagIndex: Int32) -> UInt16 {
        LiGetPortFromPortFlagIndex(portFlagIndex)
    }

    // Populates the output buffer with a stringified list of the port flags set in the input argument.
    // The second and subsequent entries will be prepended by 'separator' (if provided).
    // If the output buffer is too small, the output will be truncated to fit the provided buffer.
    @objc public static func stringifyPortFlags(portFlags: UInt32, separator: String) -> String {
        let n = 256
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: n)
        defer { buf.deallocate() }
        separator.withCString { LiStringifyPortFlags(portFlags, $0, buf, Int32(n)) }
        return String(cString: buf)
    }

    // This function may be used to test if the local network is blocking Moonlight's ports. It requires
    // a test server running on an Internet-reachable host. To perform a test, pass in the DNS hostname
    // of the test server, a reference TCP port to ensure the test host is reachable at all (something
    // very unlikely to blocked, like 80 or 443), and a set of ML_PORT_FLAG_* values corresponding to
    // the ports you'd like to test. On return, it returns ML_TEST_RESULT_INCONCLUSIVE on catastrophic error,
    // or the set of port flags that failed to validate. If all ports validate successfully, it returns 0.
    //
    // It's encouraged to not use the port flags explicitly (because GameStream ports may change in the future),
    // but to instead use ML_PORT_FLAG_ALL or LiGetPortFlagsFromStage() on connection failure.
    //
    // The test server is available at https://github.com/cgutman/gfe-loopback
    @discardableResult @objc public static func testClientConnectivity(testServer: String, referencePort: UInt16, testPortFlags: UInt32) -> UInt32 {
        testServer.withCString { LiTestClientConnectivity($0, referencePort, testPortFlags) }
    }

    // This family of functions can be used for pull-based video renderers that opt to manage a decoding/rendering
    // thread themselves. After successfully calling the WaitFor/Poll variants that dequeue the video frame, you
    // must call LiCompleteVideoFrame() to notify that processing is completed. The same DR_* status values
    // from drSubmitDecodeUnit() must be passed to LiCompleteVideoFrame() as the drStatus argument.
    //
    // In order to safely use these functions, you must set CAPABILITY_PULL_RENDERER on the video decoder.
    @objc public static func waitForNextVideoFrame(handle: AutoreleasingUnsafeMutablePointer<VideoFrameHandle?>, decodeUnit: AutoreleasingUnsafeMutablePointer<StreamDecodeUnit?>) -> Bool {
        var localHandle: UnsafeMutableRawPointer? = nil
        var duPtr: UnsafeMutablePointer<DECODE_UNIT>? = nil
        let ok = LiWaitForNextVideoFrame(&localHandle, &duPtr)
        handle.pointee = localHandle.map { VideoFrameHandle(rawHandle: $0) }
        decodeUnit.pointee = duPtr.map { StreamDecodeUnit.fromCStruct(UnsafePointer($0)) }
        return ok
    }
    @objc public static func pollNextVideoFrame(handle: AutoreleasingUnsafeMutablePointer<VideoFrameHandle?>, decodeUnit: AutoreleasingUnsafeMutablePointer<StreamDecodeUnit?>) -> Bool {
        var localHandle: UnsafeMutableRawPointer? = nil
        var duPtr: UnsafeMutablePointer<DECODE_UNIT>? = nil
        let ok = LiPollNextVideoFrame(&localHandle, &duPtr)
        handle.pointee = localHandle.map { VideoFrameHandle(rawHandle: $0) }
        decodeUnit.pointee = duPtr.map { StreamDecodeUnit.fromCStruct(UnsafePointer($0)) }
        return ok
    }
    @objc public static func peekNextVideoFrame() -> StreamDecodeUnit? {
        var duPtr: UnsafeMutablePointer<DECODE_UNIT>? = nil
        let ok = LiPeekNextVideoFrame(&duPtr)
        guard ok, let p = duPtr else { return nil }
        return StreamDecodeUnit.fromCStruct(UnsafePointer(p))
    }
    @objc public static func wakeWaitForVideoFrame() {
        LiWakeWaitForVideoFrame()
    }
    @objc public static func completeVideoFrame(handle: VideoFrameHandle?, status: Int32) {
        LiCompleteVideoFrame(handle?.rawHandle, status)
    }

    // This function returns the last reported HDR mode from the host PC.
    // See ConnListenerSetHdrMode() for more details.
    @objc public static func getCurrentHostDisplayHdrMode() -> Bool {
        LiGetCurrentHostDisplayHdrMode()
    }

    // This function populates the provided mastering metadata struct with the HDR metadata
    // from the host PC's monitor and content (if available). It is only valid to call this
    // function when HDR mode is active on the host. This is a Sunshine protocol extension.
    @objc public static func getHdrMetadata() -> SSHdrMetadata? {
        var m = SS_HDR_METADATA();
        guard LiGetHdrMetadata(&m) else { return nil };
        return SSHdrMetadata.fromCStruct(m)
    }

    // This function requests an IDR frame from the host. Typically this is done using DR_NEED_IDR, but clients
    // processing frames asynchronously may need to reset their decoder state even after returning DR_OK for
    // the prior frame. Rather than wait for a new frame and return DR_NEED_IDR for that one, they can just
    // call this API instead. Note that this function does not guarantee that the *next* frame will be an IDR
    // frame, just that an IDR frame will arrive soon.
    @objc public static func requestIdrFrame() {
        LiRequestIdrFrame()
    }

    // This function returns any extended feature flags supported by the host.
    @objc public static func getHostFeatureFlags() -> UInt32 {
        LiGetHostFeatureFlags()
    }
}
