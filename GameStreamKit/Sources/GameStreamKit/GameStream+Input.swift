import Foundation
internal import Limelight

extension GameStream {
    // This function queues a relative mouse move event to be sent to the remote server.
    @discardableResult @objc public static func sendMouseMoveEvent(deltaX: Int16, deltaY: Int16) -> Int32 {
        return LiSendMouseMoveEvent(deltaX, deltaY)
    }
    
    // This function queues a mouse position update event to be sent to the remote server.
    // This functionality is only reliably supported on GFE 3.20 or later. Earlier versions
    // may not position the mouse correctly.
    //
    // Absolute mouse motion doesn't work in many games, so this mode should not be the default
    // for mice when streaming. It may be desirable as the default touchscreen behavior when
    // LiSendTouchEvent() is not supported and the touchscreen is not the primary input method.
    // In the latter case, a touchscreen-as-trackpad mode using LiSendMouseMoveEvent() is likely
    // to be better for gaming use cases.
    //
    // The x and y values are transformed to host coordinates as if they are from a plane which
    // is referenceWidth by referenceHeight in size. This allows you to provide coordinates that
    // are relative to an arbitrary plane, such as a window, screen, or scaled video view.
    //
    // For example, if you wanted to directly pass window coordinates as x and y, you would set
    // referenceWidth and referenceHeight to your window width and height.
    @discardableResult @objc public static func sendMousePositionEvent(x: Int16, y: Int16, referenceWidth: Int16, referenceHeight: Int16) -> Int32 {
        return LiSendMousePositionEvent(x, y, referenceWidth, referenceHeight)
    }

    // This function queues a mouse position update event to be sent to the remote server, so
    // all of the limitations of LiSendMousePositionEvent() mentioned above apply here too!
    //
    // This function behaves like a combination of LiSendMouseMoveEvent() and LiSendMousePositionEvent()
    // in that it sends a relative motion event, however it sends this data as an absolute position
    // based on the computed position of a virtual client cursor which is "moved" any time that
    // LiSendMousePositionEvent() or LiSendMouseMoveAsMousePositionEvent() is called. As a result
    // of this internal virtual cursor state, callers must ensure LiSendMousePositionEvent() and
    // LiSendMouseMoveAsMousePositionEvent() are not called concurrently!
    //
    // The big advantage of this function is that it allows callers to avoid mouse acceleration that
    // would otherwise affect motion when using LiSendMouseMoveEvent(). The downside is that it has the
    // same game compatibility issues as LiSendMousePositionEvent().
    //
    // This function can be useful when mouse capture is the only feasible way to receive mouse input,
    // like on Android or iOS, and the OS cannot provide raw unaccelerated mouse motion when capturing.
    // Using this function avoids double-acceleration in cases when the client motion is also accelerated.
    @discardableResult @objc public static func sendMouseMoveAsMousePositionEvent(deltaX: Int16, deltaY: Int16, referenceWidth: Int16, referenceHeight: Int16) -> Int32 {
        return LiSendMouseMoveAsMousePositionEvent(deltaX, deltaY, referenceWidth, referenceHeight)
    }

    // This function allows multi-touch input to be sent directly to Sunshine hosts. The x and y values
    // are normalized device coordinates stretching top-left corner (0.0, 0.0) to bottom-right corner
    // (1.0, 1.0) of the video area.
    //
    // Pointer ID is an opaque ID that must uniquely identify each active touch on screen. It must
    // remain constant through any down/up/move/cancel events involved in a single touch interaction.
    //
    // Rotation is in degrees from vertical in Y dimension (parallel to screen, 0..360). If rotation is
    // unknown, pass LI_ROT_UNKNOWN.
    //
    // Pressure is a 0.0 to 1.0 range value from min to max pressure. Sending a down/move event with
    // a pressure of 0.0 indicates the actual pressure is unknown.
    //
    // For hover events, the pressure value is treated as a 1.0 to 0.0 range of distance from the touch
    // surface where 1.0 is the farthest measurable distance and 0.0 is actually touching the display
    // (which is invalid for a hover event). Reporting distance 0.0 for a hover event indicates the
    // actual distance is unknown.
    //
    // Contact area is modelled as an ellipse with major and minor axis values in normalized device
    // coordinates. If contact area is unknown, report 0.0 for both contact area axis parameters.
    // For circular contact areas or if a minor axis value is not available, pass the same value
    // for major and minor axes. For APIs or devices, that don't report contact area as an ellipse,
    // approximations can be used such as: https://docs.kernel.org/input/multi-touch-protocol.html#event-computation
    //
    // For hover events, the "contact area" is the size of the hovering finger/tool. If unavailable,
    // pass 0.0 for both contact area parameters.
    //
    // Touches can be cancelled using LI_TOUCH_EVENT_CANCEL or LI_TOUCH_EVENT_CANCEL_ALL. When using
    // LI_TOUCH_EVENT_CANCEL, only the pointerId parameter is valid. All other parameters are ignored.
    // To cancel all active touches (on focus loss, for example), use LI_TOUCH_EVENT_CANCEL_ALL.
    //
    // If unsupported by the host, this will return LI_ERR_UNSUPPORTED and the caller should consider
    // falling back to other functions to send this input (such as LiSendMousePositionEvent()).
    //
    // To determine if LiSendTouchEvent() is supported without calling it, call LiGetHostFeatureFlags()
    // and check for the LI_FF_PEN_TOUCH_EVENTS flag.
    @discardableResult @objc public static func sendTouchEvent(eventType: UInt8, pointerId: UInt32, x: Float, y: Float, pressureOrDistance: Float, contactAreaMajor: Float, contactAreaMinor: Float, rotation: UInt16) -> Int32 {
        return LiSendTouchEvent(eventType, pointerId, x, y, pressureOrDistance, contactAreaMajor, contactAreaMinor, rotation)
    }

    // This function is similar to LiSendTouchEvent() but allows additional parameters relevant for pen
    // input, including tilt and buttons. Tilt is in degrees from vertical in Z dimension (perpendicular
    // to screen, 0..90). See LiSendTouchEvent() for detailed documentation on other parameters.
    //
    // x, y, pressure, rotation, contact area, and tilt are ignored for LI_TOUCH_EVENT_BUTTON_ONLY events.
    // If one of those changes, send LI_TOUCH_EVENT_MOVE or LI_TOUCH_EVENT_HOVER instead.
    //
    // To determine if LiSendPenEvent() is supported without calling it, call LiGetHostFeatureFlags()
    // and check for the LI_FF_PEN_TOUCH_EVENTS flag.
    @discardableResult @objc public static func sendPenEvent(eventType: UInt8, toolType: UInt8, penButtons: UInt8, x: Float, y: Float, pressureOrDistance: Float, contactAreaMajor: Float, contactAreaMinor: Float, rotation: UInt16, tilt: UInt8) -> Int32 {
        return LiSendPenEvent(eventType, toolType, penButtons, x, y, pressureOrDistance, contactAreaMajor, contactAreaMinor, rotation, tilt)
    }

    // This function queues a mouse button event to be sent to the remote server.
    @discardableResult @objc public static func sendMouseButtonEvent(action: UInt8, button: Int32) -> Int32 {
        return LiSendMouseButtonEvent(CChar(action), button)
    }

    // This function queues a keyboard event to be sent to the remote server.
    // Key codes are Win32 Virtual Key (VK) codes and interpreted as keys on
    // a US English layout.
    @discardableResult @objc public static func sendKeyboardEvent(keyCode: Int16, keyAction: UInt8, modifiers: UInt8) -> Int32 {
        return LiSendKeyboardEvent(keyCode, CChar(keyAction), CChar(modifiers))
    }

    // Similar to LiSendKeyboardEvent() but allows the client to inform the host that
    // the keycode was not mapped to a standard US English scancode and should be
    // interpreted as-is. This is a Sunshine protocol extension.
    @discardableResult @objc public static func sendKeyboardEvent2(keyCode: Int16, keyAction: UInt8, modifiers: UInt8, flags: UInt8) -> Int32 {
        return LiSendKeyboardEvent2(keyCode, CChar(keyAction), CChar(modifiers), CChar(flags))
    }

    // This function queues an UTF-8 encoded text to be sent to the remote server.
    @discardableResult @objc public static func sendUtf8TextEvent(text: String) -> Int32 {
        return text.withCString { LiSendUtf8TextEvent($0, UInt32(text.utf8.count)) }
    }

    // This function queues a controller event to be sent to the remote server. It will
    // be seen by the computer as the first controller.
    @discardableResult @objc public static func sendControllerEvent(buttonFlags: Int32, leftTrigger: UInt8, rightTrigger: UInt8, leftStickX: Int16, leftStickY: Int16, rightStickX: Int16, rightStickY: Int16) -> Int32 {
        return LiSendControllerEvent(buttonFlags, leftTrigger, rightTrigger, leftStickX, leftStickY, rightStickX, rightStickY)
    }

    // This function queues a controller event to be sent to the remote server. The controllerNumber
    // parameter is a zero-based index of which controller this event corresponds to. The largest legal
    // controller number is 3 for GFE hosts and 15 for Sunshine hosts. On generation 3 servers (GFE 2.1.x),
    // these will be sent as controller 0 regardless of the controllerNumber parameter.
    //
    // The activeGamepadMask parameter is a bitfield with bits set for each controller present.
    // On GFE, activeGamepadMask is limited to a maximum of 4 bits (0xF).
    // On Sunshine, it is limited to 16 bits (0xFFFF).
    //
    // To indicate arrival of a gamepad, you may send an empty event with the controller number
    // set to the new controller and the bit of the new controller set in the active gamepad mask.
    // However, you should prefer LiSendControllerArrivalEvent() instead of this function for
    // that purpose, because it allows the host to make a better choice of emulated controller.
    //
    // To indicate removal of a gamepad, send an empty event with the controller number set to the
    // removed controller and the bit of the removed controller cleared in the active gamepad mask.
    @discardableResult @objc public static func sendMultiControllerEvent(controllerNumber: Int16, activeGamepadMask: Int16, buttonFlags: Int32, leftTrigger: UInt8, rightTrigger: UInt8, leftStickX: Int16, leftStickY: Int16, rightStickX: Int16, rightStickY: Int16) -> Int32 {
        return LiSendMultiControllerEvent(controllerNumber, activeGamepadMask, buttonFlags, leftTrigger, rightTrigger, leftStickX, leftStickY, rightStickX, rightStickY)
    }

    // This function provides a method of informing the host of the available buttons and capabilities
    // on a new controller. This is the recommended approach for indicating the arrival of a new controller.
    //
    // This can allow the host to make better decisions about what type of controller to emulate and what
    // capabilities to advertise to the OS on the virtual controller.
    //
    // If controller arrival events are unsupported by the host, this will fall back to indicating
    // arrival via LiSendMultiControllerEvent().
    @discardableResult @objc public static func sendControllerArrivalEvent(controllerNumber: UInt8, activeGamepadMask: UInt16, type: UInt8, supportedButtonFlags: UInt32, capabilities: UInt16) -> Int32 {
        return LiSendControllerArrivalEvent(controllerNumber, activeGamepadMask, type, supportedButtonFlags, capabilities)
    }

    // This function is similar to LiSendTouchEvent(), but the touch events are associated with a
    // touchpad device present on a game controller instead of a touchscreen.
    //
    // If unsupported by the host, this will return LI_ERR_UNSUPPORTED and the caller should consider
    // using this touch input to simulate trackpad input.
    //
    // To determine if LiSendControllerTouchEvent() is supported without calling it, call LiGetHostFeatureFlags()
    // and check for the LI_FF_CONTROLLER_TOUCH_EVENTS flag.
    @discardableResult @objc public static func sendControllerTouchEvent(controllerNumber: UInt8, eventType: UInt8, pointerId: UInt32, x: Float, y: Float, pressure: Float) -> Int32 {
        return LiSendControllerTouchEvent(controllerNumber, eventType, pointerId, x, y, pressure)
    }

    // This function allows clients to send controller-associated motion events to a supported host.
    //
    // For power and performance reasons, motion sensors should not be enabled unless the host has
    // explicitly asked for motion event reports via ConnListenerSetMotionEventState().
    //
    // LI_MOTION_TYPE_ACCEL should report data in m/s^2 (inclusive of gravitational acceleration).
    // LI_MOTION_TYPE_GYRO should report data in deg/s.
    //
    // The x/y/z axis assignments follow SDL's convention documented here:
    // https://github.com/libsdl-org/SDL/blob/96720f335002bef62115e39327940df454d78f6c/include/SDL3/SDL_sensor.h#L80-L124
    @discardableResult @objc public static func sendControllerMotionEvent(controllerNumber: UInt8, motionType: UInt8, x: Float, y: Float, z: Float) -> Int32 {
        return LiSendControllerMotionEvent(controllerNumber, motionType, x, y, z)
    }

    // This function allows clients to send controller battery state to a supported host. If the
    // host can adjust battery state on the emulated controller, it can use this information to
    // make the virtual controller match the physical controller on the client.
    @discardableResult @objc public static func sendControllerBatteryEvent(controllerNumber: UInt8, batteryState: UInt8, batteryPercentage: UInt8) -> Int32 {
        return LiSendControllerBatteryEvent(controllerNumber, batteryState, batteryPercentage)
    }

    // This function queues a vertical scroll event to the remote server.
    // The number of "clicks" is multiplied by WHEEL_DELTA (120) before
    // being sent to the PC.
    @discardableResult @objc public static func sendScrollEvent(scrollClicks: Int8) -> Int32 {
        return LiSendScrollEvent(scrollClicks)
    }

    // This function queues a vertical scroll event to the remote server.
    // Unlike LiSendScrollEvent(), this function can send wheel events
    // smaller than 120 units for devices that support "high resolution"
    // scrolling (Apple Trackpads, Microsoft Precision Touchpads, etc.).
    @discardableResult @objc public static func sendHighResScrollEvent(scrollAmount: Int16) -> Int32 {
        return LiSendHighResScrollEvent(scrollAmount)
    }

    // These functions send horizontal scroll events to the host which are
    // analogous to LiSendScrollEvent() and LiSendHighResScrollEvent().
    // This is a Sunshine protocol extension.
    @discardableResult @objc public static func sendHScrollEvent(scrollClicks: Int8) -> Int32 {
        return LiSendHScrollEvent(scrollClicks)
    }
    @discardableResult @objc public static func sendHighResHScrollEvent(scrollAmount: Int16) -> Int32 {
        return LiSendHighResHScrollEvent(scrollAmount)
    }
}
