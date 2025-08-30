import Foundation
internal import Limelight

@objc public class SSHdrDisplayPrimary: NSObject {
    @objc public let x: UInt16 // Normalized to 50,000
    @objc public let y: UInt16 // Normalized to 50,000
    @objc public init(x: UInt16, y: UInt16) { self.x = x; self.y = y; super.init() }
}

@objc public class SSHdrWhitePoint: NSObject {
    @objc public let x: UInt16 // Normalized to 50,000
    @objc public let y: UInt16 // Normalized to 50,000
    @objc public init(x: UInt16, y: UInt16) { self.x = x; self.y = y; super.init() }
}

@objc public class SSHdrMetadata: NSObject {
    // RGB order
    @objc public let displayPrimaries: [SSHdrDisplayPrimary]

    @objc public let whitePoint: SSHdrWhitePoint
    
    @objc public let maxDisplayLuminance: UInt16 // Nits
    @objc public let minDisplayLuminance: UInt16 // 1/10000th of a nit

    // These are content-specific values which may not be available for all hosts.
    @objc public let maxContentLightLevel: UInt16 // Nits
    @objc public let maxFrameAverageLightLevel: UInt16 // Nits

    // These are display-specific values which may not be available for all hosts.
    @objc public let maxFullFrameLuminance: UInt16 // Nits

    @objc public init(displayPrimaries: [SSHdrDisplayPrimary],
                whitePoint: SSHdrWhitePoint,
                maxDisplayLuminance: UInt16,
                minDisplayLuminance: UInt16,
                maxContentLightLevel: UInt16,
                      maxFrameAverageLightLevel: UInt16,
                      maxFullFrameLuminance: UInt16) {
        self.displayPrimaries = displayPrimaries
        self.whitePoint = whitePoint
        self.maxDisplayLuminance = maxDisplayLuminance
        self.minDisplayLuminance = minDisplayLuminance
        self.maxContentLightLevel = maxContentLightLevel
        self.maxFrameAverageLightLevel = maxFrameAverageLightLevel
        self.maxFullFrameLuminance = maxFullFrameLuminance
        super.init()
    }
    
    internal static func fromCStruct(_ cMetadata: SS_HDR_METADATA) -> SSHdrMetadata {
        let ptr = withUnsafePointer(to: cMetadata) { p in p.withMemoryRebound(to: UInt16.self, capacity: 32) { $0 } }
        let primaries = [
            SSHdrDisplayPrimary(x: ptr[0], y: ptr[1]),
            SSHdrDisplayPrimary(x: ptr[2], y: ptr[3]),
            SSHdrDisplayPrimary(x: ptr[4], y: ptr[5])
        ]
        let white = SSHdrWhitePoint(x: ptr[6], y: ptr[7])
        return SSHdrMetadata(displayPrimaries: primaries,
                             whitePoint: white,
                             maxDisplayLuminance: cMetadata.maxDisplayLuminance,
                             minDisplayLuminance: cMetadata.minDisplayLuminance,
                             maxContentLightLevel: cMetadata.maxContentLightLevel,
                             maxFrameAverageLightLevel: cMetadata.maxFrameAverageLightLevel,
                             maxFullFrameLuminance: cMetadata.maxFullFrameLuminance)
    }
}
