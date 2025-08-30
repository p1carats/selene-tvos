import Foundation
private import Limelight

extension GameStream {
    // This function begins streaming.
    //
    // Callbacks are all optional. Pass NULL for individual callbacks within each struct or pass NULL for the entire struct
    // to use the defaults for all callbacks.
    //
    // This function is not thread-safe.
    //
    @discardableResult @objc public static func startConnection(
        serverInfo: GameServerInformation,
        streamConfig: GameStreamConfiguration,
        connectionCallbacks: ConnectionDelegate,
        videoCallbacks: VideoDecoderDelegate,
        videoCapabilities: Int32 = 0,
        audioCallbacks: AudioRendererDelegate,
        audioCapabilities: Int32 = 0,
    ) -> Int32 {
        connectionDelegate = connectionCallbacks
        videoDecoderDelegate = videoCallbacks
        audioRendererDelegate = audioCallbacks

        var cServerInfo = serverInfo.toCStruct()
        var cStreamConfig = streamConfig.toCStruct()
        var connectionCallbacks = initializeConnectionCallbacks()
        var videoCallbacks = initializeVideoCallbacks(videoCapabilities)
        var audioCallbacks = initializeAudioCallbacks(audioCapabilities)
        
        let result = LiStartConnection(
            &cServerInfo, 
            &cStreamConfig, 
            &connectionCallbacks, 
            &videoCallbacks, 
            &audioCallbacks, 
            nil, 0, 
            nil, 0
        )
        
        if result != 0 {
            cleanupConnection()
        }
        
        return result
    }
    
    // This function stops streaming. This function is not thread-safe.
    @objc public static func stopConnection() {
        LiStopConnection()
        cleanupConnection()
    }
    
    // This function interrupts a pending LiStartConnection() call. This interruption happens asynchronously
    // so it is not safe to start another connection before the first LiStartConnection() call returns.
    @objc public static func interruptConnection() {
        LiInterruptConnection()
    }
    
    private static func cleanupConnection() {
        connectionDelegate = nil
        videoDecoderDelegate = nil
        audioRendererDelegate = nil
    }
}
