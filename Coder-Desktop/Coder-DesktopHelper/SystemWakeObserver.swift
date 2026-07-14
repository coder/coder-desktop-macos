import Foundation
import IOKit.pwr_mgt
import os

// From <IOKit/IOMessage.h>; the iokit_common_msg macros aren't imported into Swift.
private let kIOMessageCanSystemSleep: UInt32 = 0xE000_0270
private let kIOMessageSystemWillSleep: UInt32 = 0xE000_0280
private let kIOMessageSystemHasPoweredOn: UInt32 = 0xE000_0300

/// Calls `onWake` when the system fully wakes from sleep (never on dark wake).
/// Unlike `NSWorkspace.didWakeNotification`, IOKit power events are delivered
/// to daemons running outside a GUI login session.
final class SystemWakeObserver {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "system-wake-observer")
    private var rootPort: io_connect_t = 0
    private let onWake: @Sendable () -> Void

    init(onWake: @escaping @Sendable () -> Void) {
        self.onWake = onWake
        var notifyPort: IONotificationPortRef?
        var notifier: io_object_t = 0
        rootPort = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &notifyPort,
            { refcon, _, messageType, messageArgument in
                let observer = Unmanaged<SystemWakeObserver>.fromOpaque(refcon!).takeUnretainedValue()
                observer.handle(messageType: messageType, messageArgument: messageArgument)
            },
            &notifier
        )
        guard rootPort != 0, let notifyPort else {
            logger.error("failed to register for system power notifications")
            return
        }
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(),
            .defaultMode
        )
    }

    private func handle(messageType: natural_t, messageArgument: UnsafeMutableRawPointer?) {
        switch messageType {
        case kIOMessageSystemHasPoweredOn:
            logger.info("system woke from sleep")
            onWake()
        case kIOMessageCanSystemSleep, kIOMessageSystemWillSleep:
            // Sleep is delayed until acknowledged.
            IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
        default:
            break
        }
    }
}
