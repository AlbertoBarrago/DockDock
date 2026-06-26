import AppKit
import Foundation

struct SpotifyTrack: Equatable {
    let name: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let durationMs: Int
    let positionSec: Double
}

enum SpotifyPlayerState {
    case playing, paused, stopped, notRunning
}

/// Communicates with Spotify via AppleScript (no private APIs).
/// macOS will ask the user once for Automation permission to control Spotify.
@MainActor
final class SpotifyController: ObservableObject {
    static let shared = SpotifyController()
    private init() {}

    @Published var track: SpotifyTrack?
    @Published var playerState: SpotifyPlayerState = .notRunning
    @Published var artworkImage: NSImage?

    private var refreshTask: Task<Void, Never>?
    private var lastArtworkURL: URL?

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.spotify.client"
        }
    }

    func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Controls

    func playPause() {
        Task.detached { runAppleScript("tell application \"Spotify\" to playpause") }
        // Optimistic UI update
        playerState = playerState == .playing ? .paused : .playing
    }

    func nextTrack() {
        Task.detached { runAppleScript("tell application \"Spotify\" to next track") }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        }
    }

    func previousTrack() {
        Task.detached { runAppleScript("tell application \"Spotify\" to previous track") }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        }
    }

    // MARK: - Private

    private func refresh() async {
        guard isRunning else {
            playerState = .notRunning
            track = nil
            return
        }

        // Fetch everything in one AppleScript call — ASCII 29 (GS) as field separator.
        let script = """
        tell application "Spotify"
            set sep to ASCII character 29
            return (name of current track) & sep \
                 & (artist of current track) & sep \
                 & (album of current track) & sep \
                 & (artwork url of current track) & sep \
                 & (duration of current track) & sep \
                 & (player state as text) & sep \
                 & (player position as text)
        end tell
        """

        guard let raw = await runAppleScriptAsync(script) else {
            log("Spotify: AppleScript returned nil")
            return
        }
        let parts = raw.components(separatedBy: "\u{1D}")
        guard parts.count >= 6 else { return }

        let artURLString = parts[3].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? parts[3]
        let artURL = URL(string: artURLString)
        log("Spotify: track='\(parts[0])' state='\(parts[5])' artURL='\(parts[3])'")

        let newTrack = SpotifyTrack(
            name: parts[0],
            artist: parts[1],
            album: parts[2],
            artworkURL: artURL,
            durationMs: Int(parts[4]) ?? 0,
            positionSec: Double(parts.count > 6 ? parts[6] : "0") ?? 0
        )
        if newTrack != track { track = newTrack }

        switch parts[5].lowercased() {
        case "playing": playerState = .playing
        case "paused":  playerState = .paused
        default:        playerState = .stopped
        }

        if let artURL, artURL != lastArtworkURL {
            lastArtworkURL = artURL
            await loadArtwork(from: artURL)
        }
    }

    private func loadArtwork(from url: URL) async {
        log("Spotify: loading artwork from \(url)")
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            log("Spotify: artwork download failed for \(url)")
            return
        }
        guard let image = NSImage(data: data) else {
            log("Spotify: could not decode artwork image (\(data.count) bytes)")
            return
        }
        log("Spotify: artwork loaded ✓")
        artworkImage = image
    }
}

// MARK: - AppleScript helpers (free functions, runs off main thread)

@discardableResult
func runAppleScript(_ source: String) -> String? {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
    if let error { log("AppleScript error: \(error)") }
    return result?.stringValue
}

func runAppleScriptAsync(_ source: String) async -> String? {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            cont.resume(returning: runAppleScript(source))
        }
    }
}
