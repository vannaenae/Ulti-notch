import NotchModuleKit
import Observation
import Services
import SwiftUI

@MainActor
@Observable
public final class MediaModule: NotchModule {
    public static let descriptor = ModuleDescriptor(
        id: "app.ultinotch.media",
        name: "Now Playing",
        summary: "Shows what's playing in Music or Spotify, with controls.",
        symbolName: "music.note",
        surfaces: [.compact, .expanded],
        commands: [
            CommandDescriptor(id: "playPause", title: "Play or pause music", keywords: ["music", "spotify", "pause", "resume"], symbolName: "playpause.fill"),
            CommandDescriptor(id: "next", title: "Next track", keywords: ["skip", "music"], symbolName: "forward.fill"),
            CommandDescriptor(id: "previous", title: "Previous track", keywords: ["back", "music"], symbolName: "backward.fill"),
        ],
        permissions: [
            PermissionRequirement(.automation, target: NowPlayingService.Player.music.rawValue, reason: "Play, pause and skip songs in Music.", isRequired: false),
            PermissionRequirement(.automation, target: NowPlayingService.Player.spotify.rawValue, reason: "Play, pause and skip songs in Spotify.", isRequired: false),
        ],
        services: [NowPlayingService.key.name],
        enabledByDefault: true
    )

    public static var registration: ModuleRegistration {
        ModuleRegistration(descriptor: descriptor) { MediaModule() }
    }

    public private(set) var track: NowPlayingService.Track?
    @ObservationIgnored private var context: ModuleContext?
    @ObservationIgnored private var service: NowPlayingService?
    @ObservationIgnored private var subscription: Int?

    public init() {}

    public func activate(context: ModuleContext) async throws {
        self.context = context
        guard let service = context.acquire(NowPlayingService.key) else { return }
        self.service = service
        subscription = service.changes.subscribe { [weak self] in self?.update($0) }
        update(service.track)
    }

    public func deactivate() async {
        if let subscription { service?.changes.unsubscribe(subscription) }
        subscription = nil
        service = nil
        context = nil
    }

    public func send(_ command: NowPlayingService.Command) { service?.send(command) }

    public func perform(command id: String) async {
        switch id {
        case "playPause": send(.playPause)
        case "next": send(.next)
        case "previous": send(.previous)
        default: break
        }
    }

    private func update(_ new: NowPlayingService.Track?) {
        let isNewSong = new?.title != track?.title
        track = new
        guard let context else { return }
        if let new, new.isPlaying {
            context.publish(
                key: "nowPlaying",
                content: ActivityContent(
                    leading: .symbol("music.note"),
                    trailing: .equalizer(isPlaying: true),
                    accessibilityLabel: "Playing \(new.title) by \(new.artist)"
                ),
                requestsPeek: isNewSong
            )
        } else {
            context.withdraw(key: "nowPlaying")
        }
    }

    public func expandedView() -> AnyView? { AnyView(MediaView(module: self)) }
}

struct MediaView: View {
    let module: MediaModule

    var body: some View {
        if let track = module.track {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.artist).foregroundStyle(.secondary).lineLimit(1)
                    Text(track.player.displayName).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 18) {
                    Button { module.send(.previous) } label: { Image(systemName: "backward.fill") }
                    Button { module.send(.playPause) } label: {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                    }
                    Button { module.send(.next) } label: { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain)
            }
        } else {
            Label("Play something in Music or Spotify", systemImage: "music.note")
                .foregroundStyle(.secondary)
        }
    }
}
