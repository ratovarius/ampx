import Foundation

@MainActor
enum AmpXTransportActions {
    static func make(
        for icon: AmpXIcon,
        audioPlayer: AudioPlayer,
        playlistManager: PlaylistManager
    ) -> (() -> Void)? {
        switch icon {
        case .previous: { [weak playlistManager] in playlistManager?.previous() }
        case .play: { [weak audioPlayer] in audioPlayer?.playOrResume() }
        case .pause: { [weak audioPlayer] in audioPlayer?.pause() }
        case .stop: { [weak audioPlayer] in audioPlayer?.stop() }
        case .next: { [weak playlistManager] in playlistManager?.next() }
        default: nil
        }
    }
}
