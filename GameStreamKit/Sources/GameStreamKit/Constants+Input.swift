import Foundation

@objc public class ControllerConstants: NSObject {
    @objc public static let dsEffectPayloadSize = Int32(10)
    @objc public static let dsEffectRightTrigger = UInt8(0x04)
    @objc public static let dsEffectLeftTrigger = UInt8(0x08)

    // Button flags
    @objc public static let aFlag = Int32(0x1000)
    @objc public static let bFlag = Int32(0x2000)
    @objc public static let xFlag = Int32(0x4000)
    @objc public static let yFlag = Int32(0x8000)
    @objc public static let upFlag = Int32(0x0001)
    @objc public static let downFlag = Int32(0x0002)
    @objc public static let leftFlag = Int32(0x0004)
    @objc public static let rightFlag = Int32(0x0008)
    @objc public static let lbFlag = Int32(0x0100)
    @objc public static let rbFlag = Int32(0x0200)
    @objc public static let playFlag = Int32(0x0010)
    @objc public static let backFlag = Int32(0x0020)
    @objc public static let lsClkFlag = Int32(0x0040)
    @objc public static let rsClkFlag = Int32(0x0080)
    @objc public static let specialFlag = Int32(0x0400)

    // Extended buttons (Sunshine only)
    @objc public static let paddle1Flag = Int32(0x010000)
    @objc public static let paddle2Flag = Int32(0x020000)
    @objc public static let paddle3Flag = Int32(0x040000)
    @objc public static let paddle4Flag = Int32(0x080000)
    @objc public static let touchpadFlag = Int32(0x100000) // Touchpad buttons on Sony controllers
    @objc public static let miscFlag = Int32(0x200000) // Share/Mic/Capture/Mute buttons on various controllers

    @objc public static let typeUnknown = UInt8(0x00)
    @objc public static let typeXbox = UInt8(0x01)
    @objc public static let typePlayStation = UInt8(0x02)
    @objc public static let typeNintendo = UInt8(0x03)
    @objc public static let capAnalogTriggers = UInt16(0x01) // Reports values between 0x00 and 0xFF for trigger axes
    @objc public static let capRumble = UInt16(0x02) // Can rumble in response to ConnListenerRumble() callback
    @objc public static let capTriggerRumble = UInt16(0x04) // Can rumble triggers in response to ConnListenerRumbleTriggers() callback
    @objc public static let capTouchpad = UInt16(0x08) // Reports touchpad events via LiSendControllerTouchEvent()
    @objc public static let capAccelerometer = UInt16(0x10) // Can report accelerometer events via LiSendControllerMotionEvent()
    @objc public static let capGyroscope = UInt16(0x20) // Can report gyroscope events via LiSendControllerMotionEvent()
    @objc public static let capBatteryState = UInt16(0x40) // Reports battery state via LiSendControllerBatteryEvent()
    @objc public static let capRgbLed = UInt16(0x80) // Can set RGB LED state via ConnListenerSetControllerLED()
}

@objc public enum TouchEventType: UInt8 {
    case hover = 0x00
    case down = 0x01
    case up = 0x02
    case move = 0x03
    case cancel = 0x04
    case buttonOnly = 0x05
    case hoverLeave = 0x06
    case cancelAll = 0x07
}
@objc public class TouchConstants: NSObject {
    @objc public static let rotationUnknown = UInt16(0xFFFF)
}

@objc public enum PenToolType: UInt8 {
    case unknown = 0x00
    case pen = 0x01
    case eraser = 0x02
}
@objc public class PenButtons: NSObject {
    @objc public static let primary = UInt8(0x01)
    @objc public static let secondary = UInt8(0x02)
    @objc public static let tertiary = UInt8(0x04)
    @objc public static let tiltUnknown = UInt8(0xFF)
}

@objc public class InputConstants: NSObject {
    @objc public static let buttonActionPress = UInt8(0x07)
    @objc public static let buttonActionRelease = UInt8(0x08)
    @objc public static let buttonLeft = Int32(0x01)
    @objc public static let buttonMiddle = Int32(0x02)
    @objc public static let buttonRight = Int32(0x03)
    @objc public static let buttonX1 = Int32(0x04)
    @objc public static let buttonX2 = Int32(0x05)

    @objc public static let keyActionDown = UInt8(0x03)
    @objc public static let keyActionUp = UInt8(0x04)
    @objc public static let modifierShift = UInt8(0x01)
    @objc public static let modifierCtrl = UInt8(0x02)
    @objc public static let modifierAlt = UInt8(0x04)
    @objc public static let modifierMeta = UInt8(0x08)
    
    @objc public static let keyboardEventFlagNonNormalized = UInt8(0x01)
}

@objc public enum MotionType: UInt8 {
    case accel = 0x01
    case gyro = 0x02
}

@objc public enum BatteryState: UInt8 {
    case unknown = 0x00
    case notPresent = 0x01
    case discharging = 0x02
    case charging = 0x03
    case notCharging = 0x04 // Connected to power but not charging
    case full = 0x05
}
@objc public class BatteryConstants: NSObject {
    @objc public static let percentageUnknown: UInt8 = 0xFF
}

@objc public class HostFeatureFlags: NSObject {
    @objc public static let penTouchEvents: UInt32 = 0x01 // LiSendTouchEvent()/LiSendPenEvent() supported
    @objc public static let controllerTouchEvents: UInt32 = 0x02 // LiSendControllerTouchEvent() supported
}
