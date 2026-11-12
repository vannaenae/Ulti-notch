import Foundation

/// Typed key for a shared service. The value type is usually a protocol existential,
/// e.g. `ServiceKey<any NowPlayingService>`, so modules depend on the contract and the
/// app chooses the implementation (live, mock or a private-API adapter).
public struct ServiceKey<Service>: Hashable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
}

/// Services that hold system resources implement this so the registry can start them
/// on first use and stop them when the last consumer goes away.
@MainActor
public protocol ServiceLifecycle: AnyObject {
    func start()
    func stop()
}

/// Reference-counted service container.
///
/// A service is created and started when the first module acquires it, and stopped
/// and released when the last lease is returned. Switch off every module that uses
/// the calendar and the EventKit store, its observers and its memory are gone.
@MainActor
public final class ServiceRegistry {
    private struct Entry {
        let factory: @MainActor () -> Any
        var instance: Any?
        var leaseCount: Int
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public func register<Service>(_ key: ServiceKey<Service>, factory: @escaping @MainActor () -> Service) {
        precondition(entries[key.name]?.instance == nil, "Re-registering live service \(key.name)")
        entries[key.name] = Entry(factory: { factory() }, instance: nil, leaseCount: 0)
    }

    public func isRegistered(_ name: String) -> Bool { entries[name] != nil }

    /// Number of outstanding leases. Zero means the service is not running.
    public func leaseCount(_ name: String) -> Int { entries[name]?.leaseCount ?? 0 }

    public func isRunning(_ name: String) -> Bool { entries[name]?.instance != nil }

    public func acquire<Service>(_ key: ServiceKey<Service>) -> ServiceLease<Service>? {
        guard var entry = entries[key.name] else { return nil }

        let instance: Any
        if let existing = entry.instance {
            instance = existing
        } else {
            instance = entry.factory()
            (instance as? any ServiceLifecycle)?.start()
            entry.instance = instance
        }

        guard let typed = instance as? Service else {
            assertionFailure("Service \(key.name) has unexpected type \(type(of: instance))")
            return nil
        }

        entry.leaseCount += 1
        entries[key.name] = entry
        let name = key.name
        return ServiceLease(service: typed) { [weak self] in self?.release(name) }
    }

    private func release(_ name: String) {
        guard var entry = entries[name], entry.leaseCount > 0 else { return }
        entry.leaseCount -= 1
        if entry.leaseCount == 0 {
            (entry.instance as? any ServiceLifecycle)?.stop()
            entry.instance = nil
        }
        entries[name] = entry
    }
}

/// A claim on a running service. Release exactly once; extra calls are ignored.
/// Modules never hold leases directly: `ModuleContext` tracks them and the host
/// returns every one when the module is switched off.
@MainActor
public final class ServiceLease<Service> {
    public let service: Service
    private var onRelease: (@MainActor () -> Void)?

    init(service: Service, onRelease: @escaping @MainActor () -> Void) {
        self.service = service
        self.onRelease = onRelease
    }

    public var isReleased: Bool { onRelease == nil }

    public func release() {
        let callback = onRelease
        onRelease = nil
        callback?()
    }
}

/// Minimal multicast callback list for services with more than one consumer.
@MainActor
public final class Broadcast<Value> {
    private var handlers: [Int: @MainActor (Value) -> Void] = [:]
    private var nextID = 0

    public init() {}

    @discardableResult
    public func subscribe(_ handler: @escaping @MainActor (Value) -> Void) -> Int {
        nextID += 1
        handlers[nextID] = handler
        return nextID
    }

    public func unsubscribe(_ id: Int) { handlers[id] = nil }

    public func send(_ value: Value) {
        for handler in handlers.values { handler(value) }
    }
}
