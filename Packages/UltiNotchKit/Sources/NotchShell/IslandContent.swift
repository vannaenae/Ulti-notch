import NotchModuleKit
import Observation
import SwiftUI

/// What every island shows. Shared by all displays; expansion state is per display.
@MainActor
@Observable
public final class IslandContent {
    public var resolution = ActivityResolution.empty
    public var pages: [ModulePage] = []

    public init() {}
}

public struct ModulePage: Identifiable {
    public let id: ModuleID
    public let view: AnyView

    public init(id: ModuleID, view: AnyView) {
        self.id = id
        self.view = view
    }
}
