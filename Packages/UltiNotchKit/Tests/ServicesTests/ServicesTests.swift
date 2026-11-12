import IOKit.ps
import Testing
@testable import Services

@Suite("Services parsing")
struct ServicesTests {
    @Test func musicNotification() {
        let info: [AnyHashable: Any] = ["Player State": "Playing", "Name": "Song", "Artist": "Band", "Album": "LP"]
        let track = NowPlayingService.parse(info, player: .music)
        #expect(track == NowPlayingService.Track(title: "Song", artist: "Band", album: "LP", isPlaying: true, player: .music))
    }

    @Test func pausedAndStopped() {
        #expect(NowPlayingService.parse(["Player State": "Paused", "Name": "Song"], player: .spotify)?.isPlaying == false)
        let stopped = NowPlayingService.parse(["Player State": "Stopped", "Name": "Song"], player: .spotify)
        #expect(stopped == nil)
        let untitled = NowPlayingService.parse(["Player State": "Playing"], player: .music)
        #expect(untitled == nil)
    }

    @Test func batteryDescription() {
        let s = PowerService.parse([
            kIOPSCurrentCapacityKey: 42,
            kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: true,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        ])
        #expect(s.hasBattery && s.isCharging && s.isPluggedIn)
        #expect(s.percentText == "42%")
    }
}
