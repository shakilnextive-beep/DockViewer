# DockPeek

Windows-style window previews for the macOS Dock.

Hover a Dock icon → see every window of that app (including minimized ones) as thumbnails. Click a thumbnail to open that window.

## Features

- **Hover preview**: dark card with one thumbnail per window, Windows 11 look
- **Mac traffic lights** on each preview: 🔴 close, 🟡 minimize, 🟢 zoom
- **Minimized windows** are shown too, dimmed with a "Minimized" tag
- **Click the icon of the app in front** → all its windows minimize; click again → they come back (Windows taskbar behaviour). Can be turned off in the menu.
- **Browser tabs** (Chrome, Opera, Safari, Edge, Brave, Vivaldi, Arc): a **Windows | Tabs** switch in the popup shows every open tab. Click a tab to jump to it, 🔴 closes it, the active tab has a blue border.
  - **Grid** or **one row like the Dock** layout
  - **📷 Capture** takes a picture of every tab (switches through them, then returns to the tab you were on). Tabs you open while browsing are pictured automatically.
- **Hover speed**: fast (0.2 s), medium (0.4 s, default) or slow (0.7 s)
- Menu bar icon: permission status, click option, hover speed, launch at login, quit

## Requirements

- macOS 14 or newer (Apple Silicon or Intel)
- Swift toolchain: Xcode **or** just the Command Line Tools (`xcode-select --install`)

## Build and install

```bash
git clone <this repo>
cd DockPeek
./build.sh
open /Applications/DockPeek.app
```

`build.sh` compiles a release build, wraps it into `DockPeek.app`, signs it ad-hoc and installs it to `/Applications`.

## Permissions (first run on a new Mac)

DockPeek needs two permissions. Give them once:

1. **System Settings → Privacy & Security → Accessibility** (called *Device Control and Data Access* on newer macOS)
   → press **+**, pick `/Applications/DockPeek.app`, switch it on
2. **System Settings → Privacy & Security → Screen & System Audio Recording**
   → press **+**, pick `/Applications/DockPeek.app`, switch it on
3. Restart the app: `pkill -x DockPeek; open /Applications/DockPeek.app`

The menu bar icon shows ✓ / ✗ for each permission.

For browser tabs, macOS asks once per browser: *"DockPeek wants to control Opera"* → **Allow**. If you denied it: **Privacy & Security → Automation → DockPeek** → switch the browser on.

The app is signed with a requirement pinned to its bundle id (`local.dockpeek.app`), so rebuilding does **not** reset these permissions. If a permission ever shows ✗ while its switch is on, select DockPeek in the list, press **−**, then add it again with **+**.

## Troubleshooting

Log file: `~/Library/Logs/DockPeek.log` (cleared on every launch).

| Log line | Meaning |
|---|---|
| `launch: AX=false` | Accessibility not granted (see above) |
| `ScreenRecording=false` | No thumbnails; only app icons are shown |
| `attach: watching Dock OK` | Hover detection is working |
| `hover: no running app for X` | App X is not open, so there's nothing to preview |

## Notes

- macOS can't capture a window that was already minimized before DockPeek started; such windows show the app icon until they are opened once.
- Windows on other Spaces are not listed.
- Browsers only draw the tab in front, so background tabs have no picture until they've been shown once (or you press **Capture**). Tab pictures are kept in memory only, until DockPeek quits. Firefox has no scripting support for tabs.
- Uses the private `_AXUIElementGetWindow` API to map Accessibility windows to window IDs (long-stable, used by many window managers).

## Project layout

| File | What it does |
|---|---|
| `Sources/DockPeek/main.swift` | App start, menu bar, hover timing |
| `Sources/DockPeek/DockWatcher.swift` | Detects which Dock icon is under the mouse |
| `Sources/DockPeek/DockClickHandler.swift` | Click-to-minimize / restore on Dock icons |
| `Sources/DockPeek/WindowManager.swift` | Lists windows, captures thumbnails, focus / minimize / close / zoom |
| `Sources/DockPeek/PreviewPanel.swift` | The popup's design (SwiftUI) and placement |
| `Sources/DockPeek/BrowserTabs.swift` | Reads, switches, closes and pictures browser tabs (AppleScript) |
| `Sources/DockPeek/AX.swift` | Accessibility helpers |
| `Sources/DockPeek/Log.swift` | Log file |
| `Resources/Info.plist` | App bundle info (menu bar only app) |
| `build.sh` | Build, sign and install |
