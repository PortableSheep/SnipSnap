# Changelog

All notable changes to SnipSnap will be documented here.

## [Unreleased]

### 🔧 Changes

- Remove auto-scroll from scroll capture; manual scroll is now the only mode (more reliable stitching)

### ✨ Features

- Add auto hide to capture strip (`fa2bb22`)
- Add updater (`1904b56`)
- Add corner rounding. (`a358219`)
- Add testing infrastructure with Swift Testing framework (`51ba491`)
- Add macOS window preview and collapse PII list (`b83acd1`)
- Add desktop wallpaper background option (CleanShot X-style) (`f62ba5f`)
- Add product website with GitHub Pages deployment (`975fc96`)

### 🐛 Bug Fixes

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
