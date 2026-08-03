import Foundation
import SwiftUI

struct MusicControlsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var music: MusicBridge
    @ObservedObject private var lofi: LofiYouTubePlayer

    init(model: AppModel) {
        self.model = model
        music = model.music
        lofi = model.lofiYouTube
    }

    var body: some View {
        Group {
            if model.musicSource == .lofiGirl {
                lofiControls
            } else {
                systemPlayerControls
            }
        }
        .padding(.horizontal, 10)
        .onAppear { model.musicSurfaceDidAppear() }
        .onDisappear { model.musicSurfaceDidDisappear() }
        .onChange(of: model.musicSource) { _, source in
            model.musicSurfaceDidAppear()
            if source != .lofiGirl {
                lofi.pause()
                music.refresh()
            }
        }
    }

    private var systemPlayerControls: some View {
        HStack(spacing: 14) {
            sourcePicker
                .frame(width: 118)

            TrackArtworkView(track: music.track, size: 62)

            VStack(alignment: .leading, spacing: 3) {
                Text(trackTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(trackSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchflowTheme.secondary)
                    .lineLimit(1)
                if let error = music.lastError, !music.isAvailable {
                    Text(error)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(NotchflowTheme.orangeSoft)
                        .lineLimit(2)
                }
            }
            .frame(width: 138, alignment: .leading)

            HStack(spacing: 8) {
                NotchIconButton(
                    systemName: "backward.end.fill",
                    accessibilityLabel: "Previous track",
                    action: music.previous
                )
                NotchIconButton(
                    systemName: music.isPlaying ? "pause.fill" : "play.fill",
                    accessibilityLabel: music.isPlaying ? "Pause" : "Play",
                    prominent: true,
                    action: music.togglePlayPause
                )
                NotchIconButton(
                    systemName: "forward.end.fill",
                    accessibilityLabel: "Next track",
                    action: music.next
                )
            }

            NotchIconButton(
                systemName: "shuffle",
                accessibilityLabel: music.shuffleEnabled ? "Turn shuffle off" : "Turn shuffle on",
                isActive: music.shuffleEnabled,
                action: music.toggleShuffle
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "speaker.fill")
                    Text("Volume")
                    Spacer()
                    Text("\(Int(music.volume * 100))")
                        .monospacedDigit()
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NotchflowTheme.secondary)

                Slider(
                    value: Binding(
                        get: { music.volume },
                        set: { music.setVolume($0) }
                    ),
                    in: 0...1
                )
                .tint(NotchflowTheme.orange)
            }
            .frame(width: 112)

            if !music.isAvailable {
                Button("Open") { music.openProvider() }
                    .buttonStyle(.borderedProminent)
                    .tint(NotchflowTheme.orange)
                    .controlSize(.small)
            }
        }
        .onAppear { music.refresh() }
    }

    private var lofiControls: some View {
        HStack(alignment: .top, spacing: 16) {
            LofiYouTubePlayerView(player: lofi)
                .onAppear {
                    // Let the notch finish expanding before autoplay so the
                    // YouTube player is fully visible when playback begins.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if lofi.isPlayerVisible { lofi.play() }
                    }
                }

            VStack(alignment: .leading, spacing: 8) {
                sourcePicker

                Picker(
                    "Lofi Girl station",
                    selection: Binding(
                        get: { lofi.selectedStation },
                        set: { lofi.select($0) }
                    )
                ) {
                    ForEach(lofi.stations) { station in
                        Label(station.title, systemImage: station.systemImage)
                            .tag(station)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lofi.selectedStation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(lofi.selectedStation.subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(NotchflowTheme.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 7) {
                    NotchIconButton(
                        systemName: "backward.end.fill",
                        accessibilityLabel: "Previous Lofi Girl station",
                        action: { lofi.selectPrevious() }
                    )
                    NotchIconButton(
                        systemName: lofi.isPlaying ? "pause.fill" : "play.fill",
                        accessibilityLabel: lofi.isPlaying ? "Pause Lofi Girl" : "Play Lofi Girl",
                        prominent: true,
                        action: lofi.togglePlayPause
                    )
                    NotchIconButton(
                        systemName: "forward.end.fill",
                        accessibilityLabel: "Next Lofi Girl station",
                        action: { lofi.selectNext() }
                    )
                    NotchIconButton(
                        systemName: lofi.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        accessibilityLabel: lofi.isMuted ? "Unmute Lofi Girl" : "Mute Lofi Girl",
                        isActive: lofi.isMuted,
                        action: lofi.toggleMute
                    )
                }

                HStack(spacing: 6) {
                    Text(lofiStatus)
                    Spacer()
                    Text("\(Int(lofi.volume * 100))")
                        .monospacedDigit()
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(lofi.isPlaying ? NotchflowTheme.orangeSoft : NotchflowTheme.secondary)

                Slider(
                    value: Binding(
                        get: { lofi.volume },
                        set: { lofi.setVolume($0) }
                    ),
                    in: 0...1
                )
                .tint(NotchflowTheme.orange)

                if let error = lofi.lastError {
                    Text(error)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(NotchflowTheme.orangeSoft)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Link("Open video", destination: lofi.selectedStation.watchURL)
                    Link(
                        "Channel",
                        destination: URL(string: "https://www.youtube.com/channel/UCSJ4gkVC6NrvII8umztf0Ow")!
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourcePicker: some View {
        Picker("Music source", selection: $model.musicSource) {
            ForEach(MusicSource.allCases) { source in
                Label(source.displayName, systemImage: source.systemImage)
                    .tag(source)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
    }

    private var trackTitle: String {
        if !music.track.title.isEmpty { return music.track.title }
        return music.isAvailable ? "Nothing playing" : "Player not running"
    }

    private var trackSubtitle: String {
        if !music.track.artist.isEmpty {
            return music.track.album.isEmpty
                ? music.track.artist
                : "\(music.track.artist) · \(music.track.album)"
        }
        return model.musicSource.displayName
    }

    private var lofiStatus: String {
        switch lofi.playbackState {
        case .idle:
            "Ready"
        case .loading:
            "Loading…"
        case .ready:
            "Ready to play"
        case .playing:
            "Live · Playing"
        case .paused:
            "Paused"
        case .buffering:
            "Buffering…"
        case .ended:
            "Stream ended"
        case .failed:
            "Unavailable"
        }
    }
}
