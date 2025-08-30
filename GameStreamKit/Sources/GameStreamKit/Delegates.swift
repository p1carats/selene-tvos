import Foundation
internal import Limelight

@objc public protocol VideoDecoderDelegate: AnyObject {
    // This callback is invoked to provide details about the video stream and allow configuration of the decoder.
    // Returns 0 on success, non-zero on failure.
    @objc func setupDecoder(videoFormat: Int32, width: Int32, height: Int32, redrawRate: Int32, flags: Int32) -> Int32
    
    // This callback notifies the decoder that the stream is starting. No frames can be submitted before this callback returns.
    @objc optional func startDecoder()

    // This callback notifies the decoder that the stream is stopping. Frames may still be submitted but they may be safely discarded.
    @objc optional func stopDecoder()

    // This callback performs the teardown of the video decoder. No more frames will be submitted when this callback is invoked.
    @objc func cleanupDecoder()

    // This callback provides Annex B formatted elementary stream data to the
    // decoder. If the decoder is unable to process the submitted data for some reason,
    // it must return DR_NEED_IDR to generate a keyframe.
    @objc func submitDecodeUnit(_ decodeUnit: StreamDecodeUnit) -> Int32
}

@objc public protocol AudioRendererDelegate: AnyObject {
    // This callback initializes the audio renderer. The audio configuration parameter
    // provides the negotiated audio configuration. This may differ from the one
    // specified in the stream configuration. Returns 0 on success, non-zero on failure.
    @objc func initializeRenderer(audioConfiguration: Int32, opusConfig: OpusMultistreamConfiguration, flags: Int32) -> Int32
    
    // This callback notifies the decoder that the stream is starting. No audio can be submitted before this callback returns.
    @objc optional func startRenderer()

    // This callback notifies the decoder that the stream is stopping. Audio samples may still be submitted but they may be safely discarded.
    @objc optional func stopRenderer()

    // This callback performs the final teardown of the audio decoder. No additional audio will be submitted when this callback is invoked.
    @objc func cleanupRenderer()

    // This callback provides Opus audio data to be decoded and played. sampleLength is in bytes.
    @objc func decodeAndPlaySample(data: UnsafeMutablePointer<Int8>, length: Int32)
}

@objc public protocol ConnectionDelegate: AnyObject {
    // This callback is invoked to indicate that a stage of initialization is about to begin
    @objc func stageStarting(_ stage: Int32)

    // This callback is invoked to indicate that a stage of initialization has completed
    @objc func stageComplete(_ stage: Int32)

    // This callback is invoked to indicate that a stage of initialization has failed.
    // ConnListenerConnectionTerminated() will not be invoked because the connection was
    // not yet fully established. LiInterruptConnection() and LiStopConnection() may
    // result in this callback being invoked, but it is not guaranteed.
    @objc func stageFailed(_ stage: Int32, errorCode: Int32)

    // This callback is invoked after the connection is successfully established
    @objc func connectionStarted()

    // This callback is invoked when a connection is terminated after establishment.
    // The errorCode will be 0 if the termination was reported to be intentional
    // from the server (for example, the user closed the game). If errorCode is
    // non-zero, it means the termination was probably unexpected (loss of network,
    // crash, or similar conditions). This will not be invoked as a result of a call
    // to LiStopConnection() or LiInterruptConnection().
    @objc func connectionTerminated(errorCode: Int32)

    // This callback is invoked to rumble a gamepad. The rumble effect values
    // set in this callback are expected to persist until a future call sets a
    // different haptic effect or turns off the motors by passing 0 for both
    // motors. It is possible to receive rumble events for gamepads that aren't
    // physically present, so your callback should handle this possibility.
    @objc func rumble(controllerNumber: UInt16, lowFreqMotor: UInt16, highFreqMotor: UInt16)

    // This callback is used to notify the client of a connection status change.
    // Consider displaying an overlay for the user to notify them why their stream
    // is not performing as expected.
    @objc func connectionStatusUpdate(_ status: Int32)

    // This callback is invoked to notify the client of a change in HDR mode on
    // the host. The client will probably want to update the local display mode
    // to match the state of HDR on the host. This callback may be invoked even
    // if the stream is not using an HDR-capable codec.
    @objc func setHdrMode(enabled: Bool)

    // This callback is invoked to rumble a gamepad's triggers. For more details,
    // see the comment above on ConnListenerRumble().
    @objc func rumbleTriggers(controllerNumber: UInt16, leftTriggerMotor: UInt16, rightTriggerMotor: UInt16)

    // This callback is invoked to notify the client that the host would like motion
    // sensor reports for the specified gamepad (see LiSendControllerMotionEvent())
    // at the specified reporting rate (or as close as possible).
    //
    // If reportRateHz is 0, the host is asking for motion event reporting to stop.
    @objc func setMotionEventState(controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16)

    // This callback is invoked to notify the client of a change in the dualsense
    // adaptive trigger configuration.
    @objc optional func setAdaptiveTriggers(controllerNumber: UInt16, eventFlags: UInt8, typeLeft: UInt8, typeRight: UInt8, leftPayload: Data, rightPayload: Data)

    // This callback is invoked to set a controller's RGB LED (if present).
    @objc func setControllerLED(controllerNumber: UInt16, r: UInt8, g: UInt8, b: UInt8)
}
