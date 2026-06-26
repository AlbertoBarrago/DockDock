# DockDock

A native macOS utility that shows live window previews when you hover over Dock icons — no Electron, no private APIs, pure Swift + AppKit.

![macOS](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

## Features

- **Window previews** — hover any Dock icon to see all open windows as thumbnails
- **Spotify panel** — dedicated player card with album art, progress bar and playback controls
- **Window actions** — focus, minimize or close any window directly from the preview
- **Zero footprint** — lives in the menu bar only, no Dock icon
- **Native only** — built with public Apple APIs (Accessibility, ScreenCaptureKit, AppKit)

## Requirements

- macOS 14 Sonoma or later
- **Accessibility** permission (required — detects Dock icons and manages windows)
- **Screen Recording** permission (optional — enables window thumbnails)

## Build & Run

```bash
git clone https://github.com/AlbertoBarrago/DockDock.git
cd DockDock

# Debug build → /Applications/DockDock.app
bash make-app.sh

# Release build → /Applications/DockDock.app
bash make-release.sh
```

Or open `Package.swift` in Xcode and press **Cmd+R** — the scheme copies the fresh binary to `/Applications/DockDock.app` automatically before launch.

### Permissions

On first launch macOS will prompt for **Accessibility** access. Grant it, then relaunch.  
For window thumbnails, also grant **Screen Recording** in System Settings → Privacy & Security.

> After each new build, re-grant Screen Recording if thumbnails stop working — macOS ties the permission to the binary hash.

## Architecture

```
Sources/DockDock/
├── App/
│   ├── DockDockApp.swift       # @main entry point
│   └── AppDelegate.swift       # lifecycle, menu bar, Combine bindings
├── Core/
│   ├── DockObserver.swift      # global mouse tracking + AX Dock detection
│   ├── WindowCapture.swift     # ScreenCaptureKit (14.2+) with CGWindowList fallback
│   ├── PermissionManager.swift # Accessibility + Screen Recording gating
│   └── WindowInfo.swift        # window model
├── UI/
│   ├── PreviewPanel.swift      # floating NSPanel, routing, positioning
│   ├── PreviewGridView.swift   # thumbnail grid
│   └── ThumbnailView.swift     # single thumbnail + context menu
├── Features/
│   ├── SpotifyController.swift # AppleScript bridge, artwork loading
│   └── WindowManager.swift     # focus / minimize / close via AXUIElement
└── Settings/
    ├── AppSettings.swift        # @AppStorage preferences
    └── SettingsView.swift       # settings window
```

**Key design decisions**

- AX children enumeration instead of hit-test — more reliable on macOS 14/15
- Bundle ID matching in SCKit to handle multi-process apps (Firefox, Electron)
- `guard dismissTask == nil` pattern — prevents dismiss timer reset on rapid mouse events
- `CombineLatest($hoveredApp, $windows)` — panel refreshes when async capture completes
- Binary-preserving bundle update — `make-app.sh` never deletes the `.app`, keeping TCC permissions intact

## License

MIT © Alberto Barrago
