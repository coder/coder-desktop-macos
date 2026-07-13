import Foundation
import IOKit.pwr_mgt
import os

// IOKit message macros (iokit_common_msg) are not importable into Swift.
// Values from <IOKit/IOMessage.h>.
private let kIOMessageCanSystemSleep: UInt32 = 0xE000_0270
private let kIOMessageSystemWillSleep: UInt32 = 0xE000_0280
private let kIOMessageSystemHasPoweredOn: UInt32 = 0xE000_0300

/// Observes system power events and invokes `onWake` once the system has
/// fully woken from sleep.
///
/// `kIOMessageSystemHasPoweredOn` is only delivered on a full wake, never on
/// a dark wake, matching the semantics of `NSWorkspace.didWakeNotification`
/// while remaining deliverable to a daemon without a GUI session.
final class SystemWakeObserver {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "system-wake-observer")
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var rootPort: io_connect_t = 0
    private let onWake: @Sendable () -> Void

    init?(onWake: @escaping @Sendable () -> Void) {
        self.onWake = onWake
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(refcon, &notifyPort, { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            let observer = Unmanaged<SystemWakeObserver>.fromOpaque(refcon).takeUnretainedValue()
            observer.handle(messageType: messageType, messageArgument: messageArgument)
        }, &notifier)
        guard rootPort != 0, let notifyPort else {
            logger.error("failed to register for system power notifications")
            return nil
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
            // The system delays sleep until these are acknowledged.
            IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
        default:
            break
        }
    }

    deinit {
        if let notifyPort {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(),
                .defaultMode
            )
            IODeregisterForSystemPower(&notifier)
            IOServiceClose(rootPort)
            IONotificationPortDestroy(notifyPort)
        }
    }
}
