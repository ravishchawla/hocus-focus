# Hocus Focus for macOS

A native macOS 14+ notch utility built with SwiftUI and AppKit. It lives at the top center of the active display, expands on hover or click, and stays available across Spaces without taking a Dock slot.

## What works

- Collapsed and expanded Dynamic Island-style notch states
- Wall-clock-accurate Pomodoro timer with pause, reset, skip, custom intervals, automatic breaks, notifications, and haptic completion cues
- Dedicated coffee-break countdown
- Six procedural focus soundscapes: Calm, Rain, Study, Jazz, Cozy, and Lo‑Fi
- Apple Music playback controls, live/track metadata, shuffle, and volume control through Music's macOS scripting interface
- An embedded YouTube player for eight current Lofi Girl live stations, with the main study stream selected by default, automatic playback, station switching, mute, volume, local selection persistence, and uninterrupted audio across notch/tab changes
- Local preferences, simulated-notch mode, multi-display repositioning, optional launch at login, and a menu-bar fallback

## Build and run

The project uses Swift Package Manager, so the macOS Command Line Tools are enough; full Xcode is optional.

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "dist/Hocus Focus.app"
```

On first use, macOS may ask for Notifications permission and permission to control Apple Music. That permission is only needed for the Apple Music source. Lofi Girl playback uses YouTube's standard embedded player and requires an internet connection. The app stores preferences locally in `UserDefaults` and does not require an account.

## Keyboard and menu-bar access

The menu-bar timer icon can show the notch, start or pause the timer, begin a coffee break, open settings, or quit the app. The UI itself is designed to be controlled without moving focus away from the current app.

## Notes

- The app intentionally targets Apple Silicon and macOS 14 or later, matching the reference product's current requirements.
- Apple Music must be installed for its controls to work. If it is not running, the Music tab offers to open it.
- The standard YouTube player is shown in the expanded Music tab. Its player instance stays alive when the notch collapses or the Timer tab is selected, so the stream keeps playing until it is paused or the source changes.
- Procedural focus audio is generated locally, so it works offline and ships without third-party audio files.
