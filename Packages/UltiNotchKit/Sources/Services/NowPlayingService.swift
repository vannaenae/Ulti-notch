import Foundation
import NotchCore

/// Now Playing for Music and Spotify, via their public distributed notifications
/// (no permission needed to read). Controls go through AppleScript, which triggers the
/// Automation prompt the first time the user presses a button.
///
/// ponytail: Music + Spotify only. Universal sources (browsers, YouTube Music) come
/// with the MediaRemote adapter bridge (RISKS R1). Artwork comes with it too.
@MainActor
public final class NowPlayingService: ServiceLifecycle {
    public static let key = ServiceKey<NowPlayingService>("nowPlaying")

    public enum Player: String, Sendable, CaseIterable {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var notificationName: Notification.Name {
            switch self {
            case .music: Notification.Name("com.apple.Music.playerInfo")
            case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
            }
        }

        public var displayName: String { self == .music ? "Music" : "Spotify" }
    }

    public struct Track: Equatable, Sendable {
        public var title: String
        public var artist: String
        public var album: String
        public var isPlaying: Bool
        public var player: Player

        public init(title: String, artist: String, album: String, isPlaying: Bool, player: Player) {
            self.title = title
            self.artist = artist
            self.album = album
            self.isPlaying = isPlaying
            self.player = player
        }
    }

    public enum Command: Sendable { case playPause, next, previous }

    /// The player the user touched last. Nil when it stopped.
    public private(set) var track: Track?
    public let changes = Broadcast<Track?>()
    private var tokens: [NSObjectProtocol] = []

    public init() {}

    public func start() {
        let center = DistributedNotificationCenter.default()
        for player in Player.allCases {
            let token = center.addObserver(forName: player.notificationName, object: nil, queue: .main) { [weak self] note in
                let track = NowPlayingService.parse(note.userInfo ?? [:], player: player)
                MainActor.assumeIsolated { self?.receive(track, from: player) }
            }
            tokens.append(token)
        }
    }

    public func stop() {
        let center = DistributedNotificationCenter.default()
        for token in tokens { center.removeObserver(token) }
        tokens = []
        track = nil
    }

    public func send(_ command: Command) {
        guard let player = track?.player else { return }
        let verb = switch command {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        let source = "tell application id \"\(player.rawValue)\" to \(verb)"
        // Off the main thread: the first call blocks on the Automation permission prompt.
        Task.detached { _ = NSAppleScript(source: source)?.executeAndReturnError(nil) }
    }

    private func receive(_ new: Track?, from player: Player) {
        if let new {
            track = new
        } else if track?.player == player {
            track = nil
        } else {
            return
        }
        changes.send(track)
    }

    nonisolated static func parse(_ info: [AnyHashable: Any], player: Player) -> Track? {
        guard let state = info["Player State"] as? String, state != "Stopped",
              let title = info["Name"] as? String, !title.isEmpty
        else { return nil }
        return Track(
            title: title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            isPlaying: state == "Playing",
            player: player
        )
    }
}
