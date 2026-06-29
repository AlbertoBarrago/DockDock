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

/// Reads Spotify state via distributed notifications — zero TCC permission required.
/// Controls (play/pause/next/prev) use AppleScript and silently no-op if Automation is denied.
@MainActor
final class SpotifyController: ObservableObject {
    static let shared = SpotifyController()

    @Published var track: SpotifyTrack?
    @Published var playerState: SpotifyPlayerState = .notRunning
    @Published var artworkImage: NSImage?
    @Published var isLoadingInitialState: Bool = false

    private var playbackObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var positionTimer: Timer?
    private var lastArtworkTrackID: String?

    private init() {
        // Spotify broadcasts playback state changes — no Automation TCC needed.
        playbackObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handlePlaybackNotification(note)
        }

        // Detect when Spotify quits.
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.spotify.client" else { return }
            self?.handleSpotifyQuit()
        }
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
    }

    // Called when the SpotifyView appears. Sets the initial state without blocking.
    func startRefreshing() {
        if !isRunning {
            playerState = .notRunning
            track = nil
            return
        }
        if playerState == .notRunning { playerState = .stopped }

        // Distributed notifications + the always-running position timer keep state current
        // between hovers. Only do the expensive AppleScript fetch on the very first appearance
        // (track == nil), not on every re-hover.
        guard track == nil else { return }

        isLoadingInitialState = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.fetchCurrentState()
        }
    }

    private func fetchCurrentState() {
        // Each variable is set individually to avoid AppleScript parsing ambiguity.
        // The line-continuation backslash and short variable names like "st" can
        // confuse the AppleScript compiler in some locales / OS versions.
        let source = """
        tell application "Spotify"
            set stateName to (player state as string)
            if stateName is "stopped" then return "stopped"
            set sep to ASCII character 29
            set t to current track
            set trackPos to (player position as string)
            set trackDur to (duration of t as string)
            return stateName & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & trackDur & sep & trackPos & sep & (id of t)
        end tell
        """
        var err: NSDictionary?
        guard let raw = NSAppleScript(source: source)?.executeAndReturnError(&err).stringValue else {
            if let err { log("Spotify fetchCurrentState: \(err)") }
            isLoadingInitialState = false
            return
        }
        if raw == "stopped" { playerState = .stopped; track = nil; isLoadingInitialState = false; return }

        let parts = raw.components(separatedBy: "\u{1D}")
        guard parts.count >= 6 else { return }

        let stateStr = parts[0].lowercased()
        let pos      = Double(parts[5]) ?? 0
        let trackID  = parts.count > 6 ? parts[6] : ""

        track = SpotifyTrack(
            name: parts[1], artist: parts[2], album: parts[3],
            artworkURL: nil,
            durationMs: Int(parts[4]) ?? 0,
            positionSec: pos
        )
        switch stateStr {
        case "playing":
            playerState = .playing
            startPositionTimer(from: pos)
        default:
            playerState = .paused
        }
        if !trackID.isEmpty, trackID != lastArtworkTrackID {
            lastArtworkTrackID = trackID
            fetchArtwork(trackID: trackID)
        }
        isLoadingInitialState = false
        log("Spotify fetchCurrentState: '\(parts[1])' \(stateStr)")
    }

    func stopRefreshing() {
        // Intentionally keep the position timer running so the progress bar stays
        // current while the panel is hidden — avoids a visible jump on reopen.
    }

    // MARK: - Controls (AppleScript; silently fail if Automation denied)

    func playPause() {
        playerState = playerState == .playing ? .paused : .playing
        Task.detached { runAppleScript("tell application \"Spotify\" to playpause") }
    }

    func nextTrack() {
        Task.detached { runAppleScript("tell application \"Spotify\" to next track") }
    }

    func previousTrack() {
        Task.detached { runAppleScript("tell application \"Spotify\" to previous track") }
    }

    // MARK: - Notification handlers

    private func handlePlaybackNotification(_ note: Notification) {
        guard let info = note.userInfo else { return }

        let stateStr = (info["Player State"] as? String ?? "").lowercased()
        switch stateStr {
        case "playing":
            playerState = .playing
            let pos = (info["Playback Position"] as? Double) ?? 0
            startPositionTimer(from: pos)
        case "paused":
            playerState = .paused
            stopPositionTimer()
        default:
            playerState = .stopped
            track = nil
            stopPositionTimer()
            return
        }

        let name = info["Name"] as? String ?? ""
        guard !name.isEmpty else { return }

        let positionSec = (info["Playback Position"] as? Double) ?? 0
        let trackID     = (info["Track ID"] as? String) ?? ""

        let newTrack = SpotifyTrack(
            name: name,
            artist: info["Artist"] as? String ?? "",
            album:  info["Album"]  as? String ?? "",
            artworkURL: nil,
            durationMs: info["Duration"] as? Int ?? 0,
            positionSec: positionSec
        )
        track = newTrack
        log("Spotify: '\(name)' state=\(stateStr)")

        if !trackID.isEmpty, trackID != lastArtworkTrackID {
            lastArtworkTrackID = trackID
            fetchArtwork(trackID: trackID)
        }
    }

    private func handleSpotifyQuit() {
        playerState = .notRunning
        track = nil
        artworkImage = nil
        stopPositionTimer()
        log("Spotify: quit detected")
    }

    // MARK: - Progress timer

    private func startPositionTimer(from start: Double) {
        stopPositionTimer()
        guard let t = track else { return }
        // Seed current position from the notification value.
        if t.positionSec != start {
            track = SpotifyTrack(name: t.name, artist: t.artist, album: t.album,
                                 artworkURL: t.artworkURL, durationMs: t.durationMs,
                                 positionSec: start)
        }
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let t = self.track, self.playerState == .playing else { return }
            let next = min(t.positionSec + 1, Double(t.durationMs) / 1000)
            self.track = SpotifyTrack(name: t.name, artist: t.artist, album: t.album,
                                     artworkURL: t.artworkURL, durationMs: t.durationMs,
                                     positionSec: next)
        }
    }

    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    // MARK: - Artwork

    private func fetchArtwork(trackID: String) {
        artworkImage = nil
        let rawID = trackID.components(separatedBy: ":").last ?? trackID
        guard let oembedURL = URL(string: "https://open.spotify.com/oembed?url=spotify:track:\(rawID)") else { return }
        Task {
            guard
                let (data, _)   = try? await URLSession.shared.data(from: oembedURL),
                let json         = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let thumbStr     = json["thumbnail_url"] as? String,
                let thumbURL     = URL(string: thumbStr),
                let (imgData, _) = try? await URLSession.shared.data(from: thumbURL),
                let image        = NSImage(data: imgData)
            else {
                log("Spotify: artwork fetch failed for \(rawID)")
                return
            }
            artworkImage = image
            log("Spotify: artwork loaded ✓")
        }
    }
}

// MARK: - AppleScript helpers

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
