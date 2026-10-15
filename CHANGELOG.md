# Changelog

All notable changes to SnipSnap will be documented here.

## [Unreleased]

### 🔧 Changes

- Remove auto-scroll from scroll capture; manual scroll is now the only mode (more reliable stitching)
- Pinned images open near the cursor, remember their position and size across relaunches, can be resized much smaller, and show Copy / Edit / Send to Board / Unpin on hover (double-click edits, Esc or ⌘W unpins, ⌘C copies) with a "Copied" confirmation
- Editor: Ellipse tool in the sidebar, "Pin to Screen" (⌘⇧P) in the Export menu, and confirmation toasts for copy, quick export, and Send to Board
- Editor: non-destructive Crop tool (⌘K; Return applies, Esc cancels, undoable) applied to every export/copy/share, Ellipse shortcut (O), remembered window size/position with an image-fitted default, and material sidebars matching the toolbar
- Pinned images: opacity presets (100/75/50/30%) and click-through mode (hold ⌥ over the pin to interact again), both remembered across relaunches
- Board toolbar moves clear of the display notch
- Board uses only the dark glass background and no longer offers the Kanban template (existing cards and zones are preserved)
- Board takes keyboard focus on open; Escape dismisses the card preview or editor, then hides the board on the next press
- Editor: selection-aware inspector, multiline text and callouts with draggable tails, curved arrows, smooth pen strokes, shape recognition, loupes, duplicate (⌘D) and layer ordering, multi-select with marquee, and alignment guides (hold ⌥ to bypass)
- Editor: save editable annotations as a `.snipsnap.json` sidecar (⌘S); reopening the capture restores its layers
- Editor: arrow keys nudge the selection 1 px (⇧ for 10 px), with consecutive nudges undone as one step
- Editor: ⌘C on a selection copies the image plus the selected annotations; ⌘V in any editor pastes them as editable layers
- Editor: keyboard shortcut cheatsheet (? or ⌘/, or the toolbar keyboard button)
- Strip: "Copied ✓" confirmation on the thumbnail after copying
- Shortcuts preferences: warn when a shortcut is already used by another action (with Swap) or by macOS, and pause global hotkeys while recording a new shortcut

### ✨ Features

- Add Board: a full-screen corkboard of screenshot, link, text, and note cards with todos, zones, search/OCR, always-on-top "Pin to Screen", hotkeys (⌘⇧B, ⌥⌘⇧V, ⌥⌘⇧P), optional hot corner, and Send to Board from the strip, editor, and pinned images
- Record source app (and optionally browser tab) in capture metadata
- Add "Send to SnipSnap Board" to macOS Services for selected text, links, images, and files in supported apps
- Add auto hide to capture strip (`fa2bb22`)
- Add updater (`1904b56`)
- Add corner rounding. (`a358219`)
- Add testing infrastructure with Swift Testing framework (`51ba491`)
- Add macOS window preview and collapse PII list (`b83acd1`)
- Add desktop wallpaper background option (CleanShot X-style) (`f62ba5f`)
- Add product website with GitHub Pages deployment (`975fc96`)

### 🐛 Bug Fixes

- Fix loupes revealing blurred/redacted pixels in exports, copies, and the editor canvas
- Fix Escape in Board search hiding the board instead of clearing the search
- Fix saved/pasted annotation colors shifting by storing them in sRGB
- Fix arrow keys nudging annotations while an inspector control has focus
- Fix strip not refreshing when a capture's project sidecar can't be deleted
- Fix remapped global shortcuts still responding to the old key combination until relaunch
- Fix white fringes on rounded corners when copying captures to the clipboard
- Fix recording crash: deadlock in FloatingStopButton.containsPoint() (`f4354e1`)
- Fix PII scan hanging on large/tall images (`e203c7d`)
- Fix window/background layering - background now behind window (`6571925`)
- Fix macOS window chrome rendering and coordinates (`4d358c9`)
- Fix all build warnings (`1d3a6bb`)
- Fix PII pixelation coordinate system mismatch (`9eab3ba`)
- Fix PII reload persistence and pixelation rendering (`6c51fd2`)
- Fix redaction and wallpaper preview issues (`cc867d5`)

### 🔧 Improvements

- Tweaks on capture end. (`0fecd35`)
- Overhaul scrolling capture: auto-scroll engine + Vision-based stitching (`65fea3a`)
- Improve shortcuts preferences UI readability (`1124c03`)
- Improve PII redaction UX and simplify window chrome (`fa0a0f9`)
- Clean up all build warnings (`216d0c5`)
- Improve donation dialog UX (`a68722f`)
- Overhaul README with rich project details (`af1edb6`)
- Tweak release script (`316c2ad`)
- Clean old IPC code. Add license server code. (`0223b5a`)
- Clean up (`196f338`)

### 📦 Other Changes

- AI led refactoring. (`bb8d108`)
- Remove macOS window chrome feature (`aeef068`)
- Change Remove mode to Redact with black overlay (`ef9944c`)
- Enhance PII redaction with customizable styles and persistent suggestions (`d2249a9`)
- Rename app from SnipSnapMac to SnipSnap and add app icon (`5345aa1`)
- Replace emoji with SF Symbol in donation menu item (`2bf3482`)
- Enhance PII redaction: add 7 new detection types with full UI integration (`32c834f`)
- Convert to donationware: remove all licensing features (`134ec60`)
- Update GitHub Sponsors username in FUNDING.yml (`16cf4c6`)
- Allow release branches (`966f8e9`)
- Updates to action and scripts. (`a249452`)
- License server rotation support. (`d8b1e12`)
- Update ignore and readme (`04fb517`)
- Initial commit (`46c5c6d`)
