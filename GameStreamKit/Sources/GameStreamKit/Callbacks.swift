import Foundation
internal import Limelight

extension GameStream {
    internal static func initializeVideoCallbacks(_ capabilities: Int32) -> DECODER_RENDERER_CALLBACKS {
        var dr = DECODER_RENDERER_CALLBACKS()

        // Use this function to zero the video callbacks when allocated on the stack or heap
        LiInitializeVideoCallbacks(&dr)
        dr.setup = drSetup
        dr.start = drStart
        dr.stop = drStop
        dr.cleanup = drCleanup
        dr.submitDecodeUnit = drSubmitDecodeUnit
        dr.capabilities = capabilities
        return dr
    }

    internal static func initializeAudioCallbacks(_ capabilities: Int32) -> AUDIO_RENDERER_CALLBACKS {
        var ar = AUDIO_RENDERER_CALLBACKS()

        // Use this function to zero the audio callbacks when allocated on the stack or heap
        LiInitializeAudioCallbacks(&ar)
        ar.`init` = arInit
        ar.start = arStart
        ar.stop = arStop
        ar.cleanup = arCleanup
        ar.decodeAndPlaySample = arDecodeAndPlaySample
        ar.capabilities = capabilities
        return ar
    }
    
    internal static func initializeConnectionCallbacks() -> CONNECTION_LISTENER_CALLBACKS {
        var cl = CONNECTION_LISTENER_CALLBACKS()

        // Use this function to zero the connection callbacks when allocated on the stack or heap
        LiInitializeConnectionCallbacks(&cl)
        cl.stageStarting = clStageStarting
        cl.stageComplete = clStageComplete
        cl.stageFailed = clStageFailed
        cl.connectionStarted = clConnectionStarted
        cl.connectionTerminated = clConnectionTerminated
        cl.rumble = clRumble
        cl.connectionStatusUpdate = clConnectionStatusUpdate
        cl.setHdrMode = clSetHdrMode
        cl.rumbleTriggers = clRumbleTriggers
        cl.setMotionEventState = clSetMotionEventState
        cl.setControllerLED = clSetControllerLED
        cl.setAdaptiveTriggers = clSetAdaptiveTriggers
        return cl
    }
}
