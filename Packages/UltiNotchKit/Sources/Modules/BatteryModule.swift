import NotchModuleKit
import Observation
import Services
import SwiftUI

/// Calm by default: says nothing while the battery is fine. Speaks on plug/unplug
/// (3 s) and stays visible only while low and unplugged.
@MainActor
@Observable
public final class BatteryModule: NotchModule {
    public static let descriptor = ModuleDescriptor(
        id: "app.ultinotch.battery",
        name: "Battery",
        summary: "Shows charging and low battery around the notch.",
        symbolName: "battery.100percent.bolt",
        surfaces: [.compact, .expanded],
        services: [PowerService.key.name],
        defaultPriority: .low,
        enabledByDefault: true
    )

    public static var registration: ModuleRegistration {
        ModuleRegistration(descriptor: descriptor) { BatteryModule() }
    }

    public private(set) var snapshot: PowerService.Snapshot?
    @ObservationIgnored private var context: ModuleContext?
    @ObservationIgnored private var service: PowerService?
    @ObservationIgnored private var subscription: Int?

    public init() {}

    public func activate(context: ModuleContext) async throws {
        self.context = context
        guard let service = context.acquire(PowerService.key) else { return }
        self.service = service
        subscription = service.changes.subscribe { [weak self] in self?.update($0) }
        update(service.snapshot)
    }

    public func deactivate() async {
        if let subscription { service?.changes.unsubscribe(subscription) }
        subscription = nil
        service = nil
        context = nil
    }

    private func update(_ new: PowerService.Snapshot) {
        let old = snapshot
        snapshot = new
        guard let context, new.hasBattery else { return }
        let pct = new.percentText

        if let old, old.isPluggedIn != new.isPluggedIn {
            context.publish(
                key: "plug",
                content: ActivityContent(
                    leading: .symbol(new.isPluggedIn ? "bolt.fill" : "battery.75percent", tint: new.isPluggedIn ? .positive : .primary),
                    trailing: .text(pct),
                    accessibilityLabel: new.isPluggedIn ? "Charging, \(pct)" : "On battery, \(pct)"
                ),
                priority: .normal,
                lifetime: .transient(seconds: 3),
                requestsPeek: true
            )
        }

        if !new.isPluggedIn && new.level <= 0.2 {
            context.publish(
                key: "low",
                content: ActivityContent(
                    leading: .symbol("battery.25percent", tint: .critical),
                    trailing: .text(pct, tint: .critical),
                    accessibilityLabel: "Low battery, \(pct)"
                )
            )
        } else {
            context.withdraw(key: "low")
        }
    }

    public func expandedView() -> AnyView? { AnyView(BatteryView(module: self)) }
}

struct BatteryView: View {
    let module: BatteryModule

    var body: some View {
        if let s = module.snapshot, s.hasBattery {
            HStack(spacing: 12) {
                Image(systemName: s.isCharging ? "battery.100percent.bolt" : "battery.100percent")
                    .font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.percentText).font(.title2.bold()).monospacedDigit()
                    Text(s.isCharging ? "Charging" : s.isPluggedIn ? "Plugged in" : "On battery")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Label("No battery", systemImage: "powerplug")
        }
    }
}
