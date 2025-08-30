import Foundation
internal import Limelight

@objc public class GameServerInformation: NSObject {
    // Server host name or IP address in text form
    @objc public var address: String

    // Text inside 'appversion' tag in /serverinfo
    @objc public var serverInfoAppVersion: String?

    // Text inside 'GfeVersion' tag in /serverinfo (if present)
    @objc public var serverInfoGfeVersion: String?

    // Text inside 'sessionUrl0' tag in /resume and /launch (if present)
    @objc public var rtspSessionUrl: String?

    // Specifies the 'ServerCodecModeSupport' from the /serverinfo response.
    @objc public var serverCodecModeSupport: Int32

    @objc public init(address: String,
                      serverInfoAppVersion: String? = nil,
                      serverInfoGfeVersion: String? = nil,
                      rtspSessionUrl: String? = nil,
                      serverCodecModeSupport: Int32 = 0) {
        self.address = address
        self.serverInfoAppVersion = serverInfoAppVersion
        self.serverInfoGfeVersion = serverInfoGfeVersion
        self.rtspSessionUrl = rtspSessionUrl
        self.serverCodecModeSupport = serverCodecModeSupport
        super.init()
    }
    
    // Use this function to zero the stream configuration when allocated on the stack or heap
    @objc public func initializeFromDefaults() {
        var serverInfo = SERVER_INFORMATION()
        LiInitializeServerInformation(&serverInfo)
        self.address = String(cString: serverInfo.address)
        self.serverInfoAppVersion = serverInfoAppVersion ?? String(cString: serverInfo.serverInfoAppVersion!)
        self.serverInfoGfeVersion = serverInfoGfeVersion ?? String(cString: serverInfo.serverInfoGfeVersion!)
        self.rtspSessionUrl = rtspSessionUrl ?? ""
        self.serverCodecModeSupport = serverInfo.serverCodecModeSupport
        
    }
    
    internal func toCStruct() -> SERVER_INFORMATION {
        var serverInfo = SERVER_INFORMATION()
        LiInitializeServerInformation(&serverInfo)
        serverInfo.address = address.withCString { UnsafePointer(strdup($0)) }
        if let appVersion = serverInfoAppVersion {
            serverInfo.serverInfoAppVersion = appVersion.withCString { UnsafePointer(strdup($0)) }
        }
        if let gfeVersion = serverInfoGfeVersion {
            serverInfo.serverInfoGfeVersion = gfeVersion.withCString { UnsafePointer(strdup($0)) }
        }
        if let sessionUrl = rtspSessionUrl {
            serverInfo.rtspSessionUrl = sessionUrl.withCString { UnsafePointer(strdup($0)) }
        }
        serverInfo.serverCodecModeSupport = serverCodecModeSupport
        return serverInfo
    }
}
