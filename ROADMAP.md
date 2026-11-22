# DockPeek roadmap

Ideas for the next sessions, in the suggested order.

## 1. Fix first (current weak spots)

- [ ] **Keep pictures on disk**: tab and minimized-window pictures are lost when DockPeek quits. Save small thumbnails to `~/Library/Caches/DockPeek` so they survive restarts.
- [ ] **Mouse wheel in the one-row tab view**: a normal (vertical) wheel should scroll the row sideways.
- [ ] **Quieter log**: every hover is written to `~/Library/Logs/DockPeek.log`; log only problems.
- [ ] **Windows on other Spaces**: list them too; clicking should switch to that Space.

## 2. Most useful new features

- [ ] **Aero Peek highlight**: hovering a thumbnail fades every other window so only the real window shows.
- [ ] **Tab search**: a search box in the Tabs view (type "gmail" → only Gmail tabs).
- [ ] **Keyboard control**: ← → to pick, Enter to open, Delete to close while the popup is open.
- [ ] **Window count badge** on Dock icons, like the Windows taskbar.

## 3. More ideas

- [ ] Group tabs by website, close a whole group at once
- [ ] Find duplicate tabs and close them in one click
- [ ] Move a tab to another window / open it in a new window
- [ ] 🔊 icon on tabs that are playing sound
- [ ] Right-click menu on a window: tile left/right, full screen, close all
- [ ] Settings window: popup size, thumbnail size, theme
- [ ] Light mode popup when macOS is in light mode

## Done

- [x] Hover preview of all windows, including minimized ones
- [x] Windows 11 style popup with Mac traffic-light buttons
- [x] Click the front app's Dock icon to minimize / restore all its windows
- [x] Apps whose main window is an AXDialog (WhatsApp, Adobe)
- [x] Browser tab previews: Windows | Tabs switch, grid or one-row layout, Capture all tabs
- [x] Hover speed setting (fast / medium / slow)
- [x] Permissions survive rebuilds (signing pinned to bundle id)
