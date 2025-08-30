import Foundation
internal import Limelight

// MARK: - Video decoder closures

internal let drSetup: @convention(c) (Int32, Int32, Int32, Int32, UnsafeMutableRawPointer?, Int32) -> Int32 = {
    videoFormat, width, height, redrawRate, _, flags in
    return GameStream.videoDecoderDelegate?.setupDecoder(videoFormat: videoFormat, width: width, height: height, redrawRate: redrawRate, flags: flags) ?? -1
}

internal let drStart: @convention(c) () -> Void = {
    GameStream.videoDecoderDelegate?.startDecoder?()
}

internal let drStop: @convention(c) () -> Void = {
    GameStream.videoDecoderDelegate?.stopDecoder?()
}

internal let drCleanup: @convention(c) () -> Void = {
    GameStream.videoDecoderDelegate?.cleanupDecoder()
}

internal let drSubmitDecodeUnit: @convention(c) (UnsafeMutablePointer<DECODE_UNIT>?) -> Int32 = { decodeUnitPtr in
    guard let ptr = decodeUnitPtr else { return -1 }
    let swiftDecodeUnit = StreamDecodeUnit.fromCStruct(UnsafePointer(ptr))
    return GameStream.videoDecoderDelegate?.submitDecodeUnit(swiftDecodeUnit) ?? -1
}

// MARK: - Audio renderer closures

internal let arInit: @convention(c) (Int32, UnsafeMutablePointer<OPUS_MULTISTREAM_CONFIGURATION>?, UnsafeMutableRawPointer?, Int32) -> Int32 = {
    audioConfiguration, opusConfigPtr, _, flags in
    guard let opusConfig = opusConfigPtr?.pointee else { return -1 }
    let swiftOpus = OpusMultistreamConfiguration.fromCStruct(opusConfig)
    return GameStream.audioRendererDelegate?.initializeRenderer(audioConfiguration: audioConfiguration, opusConfig: swiftOpus, flags: flags) ?? -1
}

internal let arStart: @convention(c) () -> Void = {
    GameStream.audioRendererDelegate?.startRenderer?()
}

internal let arStop: @convention(c) () -> Void = {
    GameStream.audioRendererDelegate?.stopRenderer?()
}

internal let arCleanup: @convention(c) () -> Void = {
    GameStream.audioRendererDelegate?.cleanupRenderer()
}

internal let arDecodeAndPlaySample: @convention(c) (UnsafeMutablePointer<Int8>?, Int32) -> Void = { data, length in
    guard let data = data, length > 0 else { return }
    GameStream.audioRendererDelegate?.decodeAndPlaySample(data: data, length: length)
}

// MARK: - Connection closures

internal let clStageStarting: @convention(c) (Int32) -> Void = { stage in
    GameStream.connectionDelegate?.stageStarting(stage)
}
    
internal let clStageComplete: @convention(c) (Int32) -> Void = { stage in
    GameStream.connectionDelegate?.stageComplete(stage)
}

internal let clStageFailed: @convention(c) (Int32, Int32) -> Void = { stage, errorCode in
    GameStream.connectionDelegate?.stageFailed(stage, errorCode: errorCode)
}

internal let clConnectionStarted: @convention(c) () -> Void = {
    GameStream.connectionDelegate?.connectionStarted()
}

internal let clConnectionTerminated: @convention(c) (Int32) -> Void = { errorCode in
    GameStream.connectionDelegate?.connectionTerminated(errorCode: errorCode)
}

internal let clRumble: @convention(c) (UInt16, UInt16, UInt16) -> Void = { controllerNumber, lowFreq, highFreq in
    GameStream.connectionDelegate?.rumble(controllerNumber: controllerNumber, lowFreqMotor: lowFreq, highFreqMotor: highFreq)
}

internal let clConnectionStatusUpdate: @convention(c) (Int32) -> Void = { status in
    GameStream.connectionDelegate?.connectionStatusUpdate(status)
}

internal let clSetHdrMode: @convention(c) (Bool) -> Void = { enabled in
    GameStream.connectionDelegate?.setHdrMode(enabled: enabled)
}

internal let clRumbleTriggers: @convention(c) (UInt16, UInt16, UInt16) -> Void = { controllerNumber, left, right in
    GameStream.connectionDelegate?.rumbleTriggers(controllerNumber: controllerNumber, leftTriggerMotor: left, rightTriggerMotor: right)
}

internal let clSetMotionEventState: @convention(c) (UInt16, UInt8, UInt16) -> Void = { controllerNumber, motionType, rateHz in
    GameStream.connectionDelegate?.setMotionEventState(controllerNumber: controllerNumber, motionType: motionType, reportRateHz: rateHz)
}

internal let clSetControllerLED: @convention(c) (UInt16, UInt8, UInt8, UInt8) -> Void = { controllerNumber, r, g, b in
    GameStream.connectionDelegate?.setControllerLED(controllerNumber: controllerNumber, r: r, g: g, b: b)
}

internal let clSetAdaptiveTriggers: @convention(c) (UInt16, UInt8, UInt8, UInt8, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?) -> Void = {
    controllerNumber, eventFlags, typeLeft, typeRight, leftPtr, rightPtr in
    let n = Int(DS_EFFECT_PAYLOAD_SIZE)
    let leftData = leftPtr.map { Data(bytes: $0, count: n) } ?? Data()
    let rightData = rightPtr.map { Data(bytes: $0, count: n) } ?? Data()
    GameStream.connectionDelegate?.setAdaptiveTriggers?(controllerNumber: controllerNumber, eventFlags: eventFlags, typeLeft: typeLeft, typeRight: typeRight, leftPayload: leftData, rightPayload: rightData)
}
