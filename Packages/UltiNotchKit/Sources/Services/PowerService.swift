import Foundation
import IOKit.ps
import NotchCore

/// Battery and power source state. Event driven via IOKit run-loop source: zero cost while idle.
@MainActor
public final class PowerService: ServiceLifecycle {
    public static let key = ServiceKey<PowerService>("power")

    public struct Snapshot: Equatable, Sendable {
        public var hasBattery: Bool
        /// 0...1
        public var level: Double
        public var isCharging: Bool
        public var isPluggedIn: Bool

        public init(hasBattery: Bool, level: Double, isCharging: Bool, isPluggedIn: Bool) {
            self.hasBattery = hasBattery
            self.level = level
            self.isCharging = isCharging
            self.isPluggedIn = isPluggedIn
        }

        public var percentText: String { "\(Int((level * 100).rounded()))%" }
    }

    public private(set) var snapshot = Snapshot(hasBattery: false, level: 0, isCharging: false, isPluggedIn: true)
    public let changes = Broadcast<Snapshot>()
    private var source: CFRunLoopSource?

    public init() {}

    public func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<PowerService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.refresh() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
        refresh()
    }

    public func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    private func refresh() {
        let next = Self.read()
        guard next != snapshot else { return }
        snapshot = next
        changes.send(next)
    }

    private static func read() -> Snapshot {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as NSArray
        for item in list {
            guard let raw = IOPSGetPowerSourceDescription(info, item as CFTypeRef)?.takeUnretainedValue(),
                  let description = raw as NSDictionary as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            return parse(description)
        }
        return Snapshot(hasBattery: false, level: 0, isCharging: false, isPluggedIn: true)
    }

    /// Pure, so it can be tested without hardware.
    nonisolated static func parse(_ d: [String: Any]) -> Snapshot {
        let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
        return Snapshot(
            hasBattery: true,
            level: max > 0 ? min(1, Double(current) / Double(max)) : 0,
            isCharging: d[kIOPSIsChargingKey] as? Bool ?? false,
            isPluggedIn: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        )
    }
}
