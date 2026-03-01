# AGENTS.md

## Project Overview

Kawa is a macOS menu bar utility that lets users switch input sources (keyboard layouts/IMEs) via custom shortcuts.

## Architecture

Storyboard-based MVC with singleton controllers.

```
AppDelegate
  ├─ StatusBar.shared              (menu bar icon, click → open prefs)
  ├─ ModifierToggleMonitor.shared  (Left Option + Left Shift → Korean/Japanese toggle)
  └─ MainWindowController.shared   (preferences window)
       ├─ ShortcutViewController   (NSTableView data source/delegate)
       │    └─ ShortcutCellView    (per-row: MASShortcutView + shortcut binding)
       └─ PreferencesViewController (notification toggle, quit button)

InputSource                    (wraps TISInputSource with icon loading)
TISInputSource+Additions       (Swift extension over Carbon API)
PermanentStorage               (UserDefaults wrapper)
NotificationManager            (UNUserNotificationCenter wrapper)
```

**Data flow for input switching:**
- **Shortcut-based:** User presses shortcut → MASShortcutBinder → `ShortcutCellView.selectInput()` → `InputSource.select()` → `TISSelectInputSource()` (+ optional `NotificationManager.deliver()`)
- **Modifier toggle:** Left Option + Left Shift → `ModifierToggleMonitor.handleFlagsChanged()` → `toggle()` → Korean ↔ Japanese switch via `InputSource.select()`
- **Shift+Space toggle:** Pure CGEvent tap (`spaceConsumeTap`) handles `flagsChanged`+`keyDown`+`keyUp`. `flagsChanged` tracks Left Shift via `NX_DEVICELSHIFTKEYMASK` (0x02). `keyDown` toggles Korean↔English + consumes Space. `keyUp` consumed if corresponding `keyDown` was consumed. 한/영 외 입력소스에서는 토글 미발생 → Space 통과.

## File Map (`kawa/`)

| File | Lines | Role |
|------|-------|------|
| `AppDelegate.swift` | 34 | App entry point. Starts `ModifierToggleMonitor`, holds `StatusBar.shared`. Opens preferences on activation. |
| `StatusBar.swift` | 25 | Singleton. Creates `NSStatusItem` with template icon. Click opens preferences. |
| `MainWindowController.swift` | 24 | Singleton. Storyboard-instantiated window controller. Handles show/close/deactivate. |
| `ShortcutViewController.swift` | 35 | `NSTableViewDataSource`/`Delegate`. Creates keyboard and shortcut cells from `InputSource.sources`. |
| `ShortcutCellView.swift` | 39 | Binds `MASShortcutView` to a UserDefaults key derived from input source ID. Triggers input selection and optional notification via `NotificationManager`. |
| `InputSourceManager.swift` | 78 | `InputSource` class wrapping `TISInputSource`. Icon loading with retina/tiff/IconRef fallback chain. Static `sources` property lists all selectable keyboard input sources. |
| `TISInputSource+Additions.swift` | 46 | Swift extension on `TISInputSource`. Exposes `id`, `name`, `category`, `isSelectable`, `sourceLanguages`, `iconImageURL`, `iconRef`. |
| `PermanentStorage.swift` | 37 | UserDefaults wrapper with typed getters/setters. Keys: `show-notification`, `launched-for-the-first-time`. |
| `PreferencesViewController.swift` | ~60 | Notification toggle, modifier toggle, shift+space toggle checkboxes, quit button. Calls `ensureShiftSpaceState()` on shift+space toggle change. |
| `NotificationManager.swift` | 46 | `UNUserNotificationCenter` wrapper. Handles authorization request and notification delivery. |
| `ModifierToggleMonitor.swift` | ~270 | Singleton. CGEvent tap (flagsChanged) for Left Option+Left Shift → Korean↔Japanese. Pure CGEvent Shift+Space → Korean↔English (flagsChanged tracks LShift, keyDown/keyUp consume Space). `ensureShiftSpaceState()` manages spaceConsumeTap/localMonitor lifecycle. |
| `BridgingHeader.h` | 16 | ObjC bridging header importing `MASShortcut/Shortcut.h`. |

## Key Patterns & Conventions

- **UserDefaults key for shortcuts**: Input source ID with `.` replaced by `-` (e.g., `com.apple.keylayout.US` → `com-apple-keylayout-US`)
- **Icon loading fallback chain**: `@2x` retina URL → `.tiff` URL → original URL → `IconRef` (Carbon)
- **Carbon API wrapping**: `TISInputSource` properties accessed via `TISGetInputSourceProperty()` wrapped in a Swift extension with `Unmanaged` pointer handling
- **Singletons**: `StatusBar.shared` (stored property), `MainWindowController.shared` (lazy closure from storyboard)
- **LSUIElement**: App runs as agent (no Dock icon), menu bar only

## Build & Deploy

```bash
# Clean release build + copy to /Applications
xcodebuild -scheme kawa -configuration Release clean build
cp -R ~/Library/Developer/Xcode/DerivedData/kawa-*/Build/Products/Release/Kawa.app /Applications/Kawa.app
```

- Xcode project with Swift Package Manager (MASShortcut dependency)
- Ad-hoc code signing
- Main storyboard: `kawa/en.lproj/Main.storyboard`
- DerivedData 경로: `~/Library/Developer/Xcode/DerivedData/kawa-agaclupwaygpcncyukfujrsddkwd/`

## Troubleshooting Protocol

**버그 수정/문제 해결 시도 전 반드시 `steering.md`를 먼저 읽을 것.** 이전 시도 기록이 있으며, 같은 접근을 반복하지 않기 위함.
해결 시도 후 결과와 참고 자료(references)를 반드시 `steering.md`에 기록할 것.

## Known Issues

- **CJKV input sources**: Known Carbon bug with `TISSelectInputSource` for some CJK input methods.
- **No tests**: Zero test coverage. No test targets in the project.
- **`@objc` inference**: Turned off project-wide (commit `33c582b`).
- **Hardcoded input source IDs**: `ModifierToggleMonitor` has Korean/Japanese source IDs hardcoded.

## Improvement Opportunities

- Add unit test target and test coverage
- Consider SwiftUI migration for preferences UI
- Add accessibility support
- Make modifier toggle configurable (input source pair, key combination)
