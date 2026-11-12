import Foundation

/// Lifecycle half of the module protocol. The SwiftUI half (`NotchModule`) lives in
/// NotchModuleKit and refines this one.
@MainActor
public protocol ModuleLifecycle: AnyObject {
    /// Start observing services and publishing activities. Called when the user
    /// switches the module on, after any required permissions have been granted.
    func activate(context: ModuleContext) async throws
    /// Stop everything. After this returns the module must hold no timers, observers,
    /// tasks or file handles. The host also withdraws its activities and returns its
    /// service leases, so a forgetful module still can't leave residue behind.
    func deactivate() async
}

/// How the host builds a module. Holding the descriptor here means Settings can list
/// and describe every module without constructing any of them.
public struct ModuleRegistration {
    public let descriptor: ModuleDescriptor
    public let make: @MainActor () -> any ModuleLifecycle

    public init(descriptor: ModuleDescriptor, make: @escaping @MainActor () -> any ModuleLifecycle) {
        self.descriptor = descriptor
        self.make = make
    }
}

public enum ModuleHostError: Error, Hashable, Sendable {
    case unknownModule(ModuleID)
    case duplicateModule(ModuleID)
    case invalidDescriptor(ModuleID, [ModuleValidationIssue])
    case missingService(ModuleID, String)
}

/// The only handle a module gets to the rest of the app.
///
/// Scoped to one module: it can publish and withdraw *its own* activities and acquire
/// services, nothing else. Invalidated on deactivation, so a stray task that outlives
/// its module can't publish anything.
@MainActor
public final class ModuleContext {
    public let descriptor: ModuleDescriptor
    private weak var host: ModuleHost?
    private var leases: [@MainActor () -> Void] = []
    public private(set) var isValid = true

    init(descriptor: ModuleDescriptor, host: ModuleHost) {
        self.descriptor = descriptor
        self.host = host
    }

    public var moduleID: ModuleID { descriptor.id }

    /// Publish or update a live activity. Priority defaults to the module's class.
    public func publish(
        key: String,
        content: ActivityContent,
        priority: ActivityPriority? = nil,
        lifetime: ActivityLifetime = .ongoing,
        requestsPeek: Bool = false
    ) {
        guard isValid, let host else { return }
        let activity = LiveActivity(
            id: .init(module: descriptor.id, key: key),
            priority: priority ?? descriptor.defaultPriority,
            lifetime: lifetime,
            content: content,
            requestsPeek: requestsPeek
        )
        host.upsert(activity)
    }

    public func withdraw(key: String) {
        guard isValid, let host else { return }
        host.withdraw(.init(module: descriptor.id, key: key))
    }

    /// Acquire a shared service. The lease is held until the module is deactivated.
    public func acquire<Service>(_ key: ServiceKey<Service>) -> Service? {
        guard isValid, let lease = host?.services.acquire(key) else { return nil }
        leases.append { lease.release() }
        return lease.service
    }

    func invalidate() {
        isValid = false
        let pending = leases
        leases.removeAll()
        pending.forEach { $0() }
    }
}

/// Owns module lifecycle and the activity board for the whole app.
@MainActor
public final class ModuleHost {
    private struct Running {
        let instance: any ModuleLifecycle
        let context: ModuleContext
    }

    public let services: ServiceRegistry
    public var policy: ArbitrationPolicy {
        didSet { publishResolution() }
    }
    /// Called whenever what the island should show changes.
    public var onResolutionChange: (@MainActor (ActivityResolution) -> Void)?

    public private(set) var board = ActivityBoard()
    public private(set) var resolution = ActivityResolution.empty

    private let now: @MainActor () -> Date
    private var registrations: [ModuleID: ModuleRegistration] = [:]
    private var running: [ModuleID: Running] = [:]
    /// Modules mid-transition, mapped to the state the user asked for most recently.
    private var pending: [ModuleID: Bool] = [:]

    public init(
        services: ServiceRegistry? = nil,
        policy: ArbitrationPolicy = ArbitrationPolicy(),
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.services = services ?? ServiceRegistry()
        self.policy = policy
        self.now = now
    }

    // MARK: Registration

    public func register(_ registration: ModuleRegistration) throws {
        let descriptor = registration.descriptor
        guard registrations[descriptor.id] == nil else { throw ModuleHostError.duplicateModule(descriptor.id) }
        let issues = descriptor.validationIssues
        guard issues.isEmpty else { throw ModuleHostError.invalidDescriptor(descriptor.id, issues) }
        if let missing = descriptor.services.first(where: { !services.isRegistered($0) }) {
            throw ModuleHostError.missingService(descriptor.id, missing)
        }
        registrations[descriptor.id] = registration
    }

    public var descriptors: [ModuleDescriptor] {
        registrations.values.map(\.descriptor).sorted { $0.id < $1.id }
    }

    public var activeModules: Set<ModuleID> { Set(running.keys) }

    public func isActive(_ id: ModuleID) -> Bool { running[id] != nil }

    /// The live instance, for the UI layer to ask for views. Nil while disabled.
    public func instance(of id: ModuleID) -> (any ModuleLifecycle)? { running[id]?.instance }

    // MARK: Enable / disable

    /// Switches a module on or off. Rapid toggles are coalesced: the last request wins.
    public func setEnabled(_ enabled: Bool, for id: ModuleID) async throws {
        guard let registration = registrations[id] else { throw ModuleHostError.unknownModule(id) }

        if pending[id] != nil {
            pending[id] = enabled
            return
        }
        pending[id] = enabled
        defer { pending[id] = nil }

        var target = enabled
        while true {
            if target && running[id] == nil {
                try await start(registration)
            } else if !target, running[id] != nil {
                await stop(id)
            }
            guard let latest = pending[id], latest != target else { break }
            target = latest
        }
    }

    private func start(_ registration: ModuleRegistration) async throws {
        let id = registration.descriptor.id
        let context = ModuleContext(descriptor: registration.descriptor, host: self)
        let instance = registration.make()
        running[id] = Running(instance: instance, context: context)
        do {
            try await instance.activate(context: context)
        } catch {
            await stop(id)
            throw error
        }
    }

    private func stop(_ id: ModuleID) async {
        guard let entry = running[id] else { return }
        // `deactivate` must be idempotent: it also runs when `activate` throws part way.
        await entry.instance.deactivate()
        entry.context.invalidate()
        running[id] = nil
        board.withdrawAll(from: id)
        publishResolution()
    }

    // MARK: Activities

    fileprivate func upsert(_ activity: LiveActivity) {
        board.upsert(activity, now: now())
        publishResolution()
    }

    fileprivate func withdraw(_ id: LiveActivity.ID) {
        if board.withdraw(id) != nil { publishResolution() }
    }

    /// Call when `resolution.nextChange` is reached.
    public func refresh() {
        board.pruneExpired(now: now())
        publishResolution()
    }

    private func publishResolution() {
        let next = board.resolve(now: now(), policy: policy)
        guard next != resolution else { return }
        resolution = next
        onResolutionChange?(next)
    }
}
