import AppKit
import Modules
import NotchModuleKit
import NotchShell
import Observation
import Services
import SwiftUI

@main
struct UltiNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Ulti Notch", systemImage: "capsule.fill") {
            MenuContent()
        }
        Settings {
            SettingsView(model: delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.start() }
    }
}

/// Composition root: the only place that knows every service and module.
@MainActor
@Observable
final class AppModel {
    let registrations: [ModuleRegistration] = [
        MediaModule.registration,
        BatteryModule.registration,
    ]
    private(set) var enabled: Set<ModuleID> = []
    @ObservationIgnored let host: ModuleHost
    @ObservationIgnored let content = IslandContent()
    @ObservationIgnored private var displays: DisplayManager?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init() {
        let services = ServiceRegistry()
        services.register(PowerService.key) { PowerService() }
        services.register(NowPlayingService.key) { NowPlayingService() }
        host = ModuleHost(services: services)
        for registration in registrations {
            // First-party descriptors are validated by unit tests; a failure here is a programmer error.
            do { try host.register(registration) } catch { assertionFailure("\(error)") }
        }
        host.onResolutionChange = { [weak self] in self?.resolutionChanged($0) }
    }

    var descriptors: [ModuleDescriptor] { registrations.map(\.descriptor) }

    func start() async {
        displays = DisplayManager(content: content)
        for descriptor in descriptors where isEnabledInSettings(descriptor) {
            await setEnabled(true, descriptor.id)
        }
    }

    func setEnabled(_ on: Bool, _ id: ModuleID) async {
        UserDefaults.standard.set(on, forKey: Self.key(id))
        do {
            try await host.setEnabled(on, for: id)
        } catch {
            UserDefaults.standard.set(false, forKey: Self.key(id))
        }
        enabled = host.activeModules
        content.pages = descriptors.compactMap { descriptor in
            guard let module = host.instance(of: descriptor.id) as? any NotchModule,
                  let view = module.expandedView() else { return nil }
            return ModulePage(id: descriptor.id, view: view)
        }
    }

    private func isEnabledInSettings(_ descriptor: ModuleDescriptor) -> Bool {
        UserDefaults.standard.object(forKey: Self.key(descriptor.id)) as? Bool ?? descriptor.enabledByDefault
    }

    private static func key(_ id: ModuleID) -> String { "module.\(id.rawValue).enabled" }

    private func resolutionChanged(_ resolution: ActivityResolution) {
        content.resolution = resolution
        displays?.resolutionChanged()
        refreshTask?.cancel()
        guard let next = resolution.nextChange else { return }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.host.refresh()
        }
    }
}

struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Ulti Notch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Modules") {
                ForEach(model.descriptors) { descriptor in
                    ModuleRow(descriptor: descriptor, model: model)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

/// Every setting explains itself: name, one-line summary, icon.
struct ModuleRow: View {
    let descriptor: ModuleDescriptor
    let model: AppModel
    @State private var isOn: Bool

    init(descriptor: ModuleDescriptor, model: AppModel) {
        self.descriptor = descriptor
        self.model = model
        _isOn = State(initialValue: model.enabled.contains(descriptor.id))
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.name)
                    Text(descriptor.summary).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: descriptor.symbolName)
            }
        }
        .onChange(of: isOn) { _, on in
            Task { await model.setEnabled(on, descriptor.id) }
        }
    }
}
