import SwiftUI

struct SpotifyView: View {
    @ObservedObject private var spotify = SpotifyController.shared

    var body: some View {
        VStack(spacing: 0) {
            if spotify.playerState == .notRunning {
                notRunning
            } else {
                player
            }
        }
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onAppear { spotify.startRefreshing() }
        .onDisappear { spotify.stopRefreshing() }
    }

    // MARK: - Player

    private var player: some View {
        VStack(spacing: 0) {
            artwork
                .padding([.top, .horizontal], 12)
                .padding(.bottom, 10)

            VStack(spacing: 10) {
                trackInfo
                progressBar
                controls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Artwork

    private var artwork: some View {
        ZStack {
            if let img = spotify.artworkImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
        .frame(width: 236, height: 236)
    }

    // MARK: - Track info

    private var trackInfo: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(spotify.track?.name ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(spotify.track?.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            // Spotify green dot — playing indicator
            Circle()
                .fill(spotify.playerState == .playing ? Color(red: 0.11, green: 0.73, blue: 0.33) : .secondary.opacity(0.4))
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 3)
                    Capsule()
                        .fill(Color(red: 0.11, green: 0.73, blue: 0.33))
                        .frame(width: geo.size.width * progress, height: 3)
                }
            }
            .frame(height: 3)

            HStack {
                Text(formatTime(spotify.track?.positionSec ?? 0))
                Spacer()
                Text(formatTime(Double((spotify.track?.durationMs ?? 0)) / 1000))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 0) {
            Spacer()
            controlBtn(symbol: "backward.fill", size: 16) { spotify.previousTrack() }
            Spacer()
            controlBtn(
                symbol: spotify.playerState == .playing ? "pause.fill" : "play.fill",
                size: 22
            ) { spotify.playPause() }
            Spacer()
            controlBtn(symbol: "forward.fill", size: 16) { spotify.nextTrack() }
            Spacer()
        }
    }

    private func controlBtn(symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Not running

    private var notRunning: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Spotify is not running")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    // MARK: - Helpers

    private var progress: CGFloat {
        guard let t = spotify.track, t.durationMs > 0 else { return 0 }
        return min(1, CGFloat(t.positionSec) / CGFloat(t.durationMs / 1000))
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
