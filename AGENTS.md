# AGENTS.md

## Project Overview

Kawa is a macOS menu bar utility that lets users switch input sources (keyboard layouts/IMEs) via custom shortcuts.

- **Language**: Swift 5.0
- **Frameworks**: Cocoa (AppKit), Carbon (TIS* APIs)
- **Dependency**: MASShortcut 2.4.0 via Carthage
- **Bundle ID**: net.noraesae.Kawa
- **Version**: 1.1.0
- **Category**: Utility (LSUIElement = true, no Dock icon)

## Architecture

Storyboard-based MVC with singleton controllers.

```
AppDelegate
  └─ StatusBar.shared          (menu bar icon, click → open prefs)
  └─ MainWindowController.shared (preferences window)
       ├─ ShortcutViewController   (NSTableView data source/delegate)
       │    └─ ShortcutCellView    (per-row: MASShortcutView + shortcut binding)
       └─ PreferencesViewController (notification toggle, quit button)

InputSource                    (wraps TISInputSource with icon loading)
TISInputSource+Additions       (Swift extension over Carbon API)
PermanentStorage               (UserDefaults wrapper)
```

**Data flow for input switching:**
User presses shortcut → MASShortcutBinder → `ShortcutCellView.selectInput()` → `InputSource.select()` → `TISSelectInputSource()`

## File Map (`kawa/`)

| File | Lines | Role |
|------|-------|------|
| `AppDelegate.swift` | 32 | App entry point. Holds `StatusBar.shared` reference. Opens preferences on activation. |
| `StatusBar.swift` | 25 | Singleton. Creates `NSStatusItem` with template icon. Click opens preferences. |
| `MainWindowController.swift` | 24 | Singleton. Storyboard-instantiated window controller. Handles show/close/deactivate. |
| `ShortcutViewController.swift` | 33 | `NSTableViewDataSource`/`Delegate`. Creates keyboard and shortcut cells from `InputSource.sources`. |
| `ShortcutCellView.swift` | 45 | Binds `MASShortcutView` to a UserDefaults key derived from input source ID. Triggers input selection and optional notification. |
| `InputSourceManager.swift` | 74 | `InputSource` class wrapping `TISInputSource`. Icon loading with retina/tiff/IconRef fallback chain. Static `sources` property lists all selectable keyboard input sources. |
| `TISInputSource+Additions.swift` | 46 | Swift extension on `TISInputSource`. Exposes `id`, `name`, `category`, `isSelectable`, `sourceLanguages`, `iconImageURL`, `iconRef`. |
| `PermanentStorage.swift` | 39 | UserDefaults wrapper with typed getters/setters. Keys: `show-notification`, `launched-for-the-first-time`. |
| `PreferencesViewController.swift` | 31 | Notification toggle checkbox and quit button. Private `Bool`/`NSControl.StateValue` conversion extensions. |
| `BridgingHeader.h` | 16 | ObjC bridging header importing `MASShortcut/Shortcut.h`. |

## Key Patterns & Conventions

- **UserDefaults key for shortcuts**: Input source ID with `.` replaced by `-` (e.g., `com.apple.keylayout.US` → `com-apple-keylayout-US`)
- **Icon loading fallback chain**: `@2x` retina URL → `.tiff` URL → original URL → `IconRef` (Carbon)
- **Carbon API wrapping**: `TISInputSource` properties accessed via `TISGetInputSourceProperty()` wrapped in a Swift extension with `Unmanaged` pointer handling
- **Singletons**: `StatusBar.shared` (stored property), `MainWindowController.shared` (lazy closure from storyboard)
- **LSUIElement**: App runs as agent (no Dock icon), menu bar only

## Build & Development

```bash
# Install dependencies
carthage bootstrap --platform macOS

# Build
open kawa.xcodeproj
# Build with Xcode (Cmd+B)
```

- Xcode project, no Swift Package Manager
- Ad-hoc code signing
- Main storyboard: `kawa/en.lproj/Main.storyboard`

## Known Issues

- **Deprecated notification API**: Uses `NSUserNotificationCenter` (removed in macOS 11.0). Should migrate to `UserNotifications` framework.
- **CJKV input sources**: Known Carbon bug with `TISSelectInputSource` for some CJK input methods.
- **No tests**: Zero test coverage. No test targets in the project.
- **`@objc` inference**: Turned off project-wide (commit `33c582b`).

## Improvement Opportunities

- Migrate from `NSUserNotificationCenter` to `UserNotifications` framework
- Add unit test target and test coverage
- Consider SwiftUI migration for preferences UI
- Migrate from Carthage to Swift Package Manager for MASShortcut
- Add accessibility support
