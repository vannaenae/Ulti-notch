import Foundation
import Testing
@testable import NotchCore

// MARK: - Test doubles

@MainActor
final class FakeClockService: ServiceLifecycle {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
protocol ClockServicing: AnyObject {}
extension FakeClockService: ClockServicing {}

let clockKey = ServiceKey<any ClockServicing>("clock")

/// Main-actor box so `@MainActor` closures (implicitly Sendable in Swift 6) can count.
@MainActor
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor
final class FakeModule: ModuleLifecycle {
    var activateCount = 0
    var deactivateCount = 0
    var failActivation = false
    var acquireClock = false
    private(set) var context: ModuleContext?

    func activate(context: ModuleContext) async throws {
        activateCount += 1
        self.context = context
        if acquireClock { _ = context.acquire(clockKey) }
        context.publish(
            key: "main",
            content: ActivityContent(leading: .symbol("star"), trailing: .none, accessibilityLabel: "fake")
        )
        if failActivation { throw FakeError.boom }
    }

    func deactivate() async {
        deactivateCount += 1
    }
}

enum FakeError: Error { case boom }

func descriptor(_ id: ModuleID, services: [String] = []) -> ModuleDescriptor {
    ModuleDescriptor(
        id: id,
        name: "Fake",
        summary: "Test module",
        symbolName: "star",
        surfaces: [.compact, .expanded],
        services: services
    )
}

// MARK: - Tests

@Suite("Service registry")
@MainActor
struct ServiceRegistryTests {
    @Test func startsOnFirstLeaseAndStopsOnLast() {
        let registry = ServiceRegistry()
        let made = Box(0)
        let service = FakeClockService()
        registry.register(clockKey) {
            made.value += 1
            return service
        }

        #expect(!registry.isRunning("clock"))
        let a = registry.acquire(clockKey)
        let b = registry.acquire(clockKey)
        #expect(made.value == 1)
        #expect(service.startCount == 1)
        #expect(registry.leaseCount("clock") == 2)

        a?.release()
        a?.release() // double release is ignored
        #expect(registry.leaseCount("clock") == 1)
        #expect(service.stopCount == 0)

        b?.release()
        #expect(service.stopCount == 1)
        #expect(!registry.isRunning("clock"))
    }

    @Test func unknownServiceReturnsNil() {
        let lease = ServiceRegistry().acquire(ServiceKey<Int>("missing"))
        let isMissing = lease == nil
        #expect(isMissing)
    }
}

@Suite("Module host")
@MainActor
struct ModuleHostTests {
    let id: ModuleID = "app.ultinotch.fake"

    @Test func disabledModulesAreNeverConstructed() throws {
        let host = ModuleHost()
        let constructed = Box(0)
        try host.register(ModuleRegistration(descriptor: descriptor(id)) {
            constructed.value += 1
            return FakeModule()
        })
        #expect(host.descriptors.map(\.id) == [id])
        #expect(constructed.value == 0)
        let hasInstance = host.instance(of: id) != nil
        #expect(!hasInstance)
    }

    @Test func enableAndDisableLeaveNoResidue() async throws {
        let services = ServiceRegistry()
        let clock = FakeClockService()
        services.register(clockKey) { clock }

        let host = ModuleHost(services: services)
        let module = FakeModule()
        module.acquireClock = true
        try host.register(ModuleRegistration(descriptor: descriptor(id, services: ["clock"])) { module })

        let resolutions = Box<[ActivityResolution]>([])
        host.onResolutionChange = { resolutions.value.append($0) }

        try await host.setEnabled(true, for: id)
        #expect(host.isActive(id))
        #expect(module.activateCount == 1)
        #expect(services.isRunning("clock"))
        #expect(host.resolution.primary?.id.module == id)

        try await host.setEnabled(false, for: id)
        #expect(!host.isActive(id))
        #expect(module.deactivateCount == 1)
        #expect(!services.isRunning("clock"), "service stopped with its last consumer")
        #expect(clock.stopCount == 1)
        #expect(host.board.activities.isEmpty, "activities withdrawn")
        #expect(host.resolution == .empty)
        #expect(resolutions.value.count == 2)

        // A stray task holding the old context can no longer publish.
        module.context?.publish(key: "late", content: .init(leading: .none, trailing: .none, accessibilityLabel: ""))
        #expect(host.board.activities.isEmpty)
        #expect(module.context?.isValid == false)
    }

    @Test func failedActivationRollsBack() async throws {
        let host = ModuleHost()
        let module = FakeModule()
        module.failActivation = true
        try host.register(ModuleRegistration(descriptor: descriptor(id)) { module })

        await #expect(throws: FakeError.self) { try await host.setEnabled(true, for: id) }
        #expect(!host.isActive(id))
        #expect(module.deactivateCount == 1)
        #expect(host.board.activities.isEmpty)
    }

    @Test func enablingTwiceIsIdempotent() async throws {
        let host = ModuleHost()
        let module = FakeModule()
        try host.register(ModuleRegistration(descriptor: descriptor(id)) { module })
        try await host.setEnabled(true, for: id)
        try await host.setEnabled(true, for: id)
        #expect(module.activateCount == 1)
    }

    @Test func rejectsDuplicateAndInvalidModules() throws {
        let host = ModuleHost()
        try host.register(ModuleRegistration(descriptor: descriptor(id)) { FakeModule() })
        #expect(throws: ModuleHostError.duplicateModule(id)) {
            try host.register(ModuleRegistration(descriptor: descriptor(id)) { FakeModule() })
        }
        #expect(throws: ModuleHostError.self) {
            try host.register(ModuleRegistration(descriptor: descriptor("Bad ID")) { FakeModule() })
        }
        #expect(throws: ModuleHostError.missingService("app.ultinotch.other", "nope")) {
            try host.register(ModuleRegistration(descriptor: descriptor("app.ultinotch.other", services: ["nope"])) { FakeModule() })
        }
    }

    @Test func unknownModuleThrows() async {
        await #expect(throws: ModuleHostError.unknownModule(id)) {
            try await ModuleHost().setEnabled(true, for: id)
        }
    }
}

@Suite("Module descriptor rules")
struct ModuleDescriptorTests {
    @Test func idFormat() {
        #expect(ModuleID("app.ultinotch.media").isWellFormed)
        #expect(ModuleID("com.example.my-plugin").isWellFormed)
        #expect(!ModuleID("media").isWellFormed)
        #expect(!ModuleID("App.UltiNotch.Media").isWellFormed)
        #expect(!ModuleID("app..media").isWellFormed)
    }

    @Test func firstLaunchNeedsZeroPermissions() {
        let d = ModuleDescriptor(
            id: "app.ultinotch.calendar",
            name: "Calendar",
            summary: "Today and next meeting",
            symbolName: "calendar",
            surfaces: [.expanded],
            permissions: [PermissionRequirement(.calendars, reason: "Show your events in the notch.")],
            enabledByDefault: true
        )
        #expect(d.validationIssues.contains(.enabledByDefaultButNeedsPermission))
    }

    @Test func optionalPermissionsAllowDefaultOn() {
        let d = ModuleDescriptor(
            id: "app.ultinotch.media",
            name: "Media",
            summary: "Now playing",
            symbolName: "music.note",
            surfaces: [.compact, .expanded],
            permissions: [PermissionRequirement(.automation, target: "com.spotify.client", reason: "Control Spotify playback.", isRequired: false)],
            enabledByDefault: true
        )
        #expect(d.validationIssues.isEmpty)
    }

    @Test func networkModulesAreOptIn() {
        let d = ModuleDescriptor(
            id: "app.ultinotch.weather",
            name: "Weather",
            summary: "Current conditions",
            symbolName: "cloud.sun",
            surfaces: [.compact],
            enabledByDefault: true,
            usesNetwork: true
        )
        #expect(d.validationIssues == [.enabledByDefaultButUsesNetwork])
    }

    @Test func commandIDsMustBeUnique() {
        let command = CommandDescriptor(id: "start", title: "Start", symbolName: "play")
        let d = ModuleDescriptor(
            id: "app.ultinotch.pomodoro",
            name: "Pomodoro",
            summary: "Focus timer",
            symbolName: "timer",
            surfaces: [.shelfWidget],
            commands: [command, command]
        )
        #expect(d.validationIssues == [.duplicateCommandID])
    }

    @Test func descriptorRoundTripsThroughJSON() throws {
        let d = ModuleDescriptor(
            id: "app.ultinotch.media",
            name: "Media",
            summary: "Now playing",
            symbolName: "music.note",
            surfaces: [.compact, .expanded, .settings, .shelfWidget],
            commands: [CommandDescriptor(id: "playPause", title: "Play or pause", keywords: ["music"], symbolName: "playpause")],
            permissions: [PermissionRequirement(.automation, target: "com.apple.Music", reason: "Control Music.", isRequired: false)],
            services: ["nowPlaying"],
            usesPrivateAPI: true
        )
        let data = try JSONEncoder().encode(d)
        #expect(try JSONDecoder().decode(ModuleDescriptor.self, from: data) == d)
    }
}
