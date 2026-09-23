# Video Splitview v0.0.48

**Side by side, frame by frame.**

Desktop video comparison for Windows and Linux — 100% Flutter, powered by the
**libmpv** engine (via `media_kit`). UI and video are composed in the same Flutter
scene, with no overlapping native layers.

## Highlights

- Compare **1 to 4 videos** at once, each in its own layout cell.
- **Drag & drop** files onto a panel or click to open (multi-select supported).
- **Wipe**, **Columns** and **Blink** view modes.
- Frame-accurate sync with drift correction, frame stepping and jog.
- Rich on-video HUD: FPS, frame, buffer, desync (Δ ms) and full per-video statistics.
- Save/copy the comparison as a PNG.

## Features

### Videos and layout

- **1, 2, 3 or 4 videos** in a single view. The top bar switches to a compact layout
  for 3–4 videos so all side groups fit.
- **Open / change / remove** per side, plus **rotate** (rotate that video 90°) and
  **mute**.
- **Drag & drop**: drop one or more files onto a panel. With multiple files the view
  count is adjusted to `min(n, 4)` and the files are assigned to the active sides in
  order.
- **Split layouts**:
  - 2 videos: side by side, stacked.
  - 3 videos: 3 columns, 3 rows, two on top + one below, one on top + two below, one
    left + two right, two left + one right.
  - 4 videos: 2×2 grid, 4 columns, 4 rows, three on top + one below, one on top +
    three below, one left + three right, three left + one right.
- **Rotate positions** (reshuffle which video sits in which cell) and **rotate all
  videos** 90°.

### View modes

- **Wipe** — videos overlaid; the divider reveals one over the other.
- **Columns** — each video drawn in its layout cell.
- **Blink** — toggles A↔B on a timer (100–1000 ms), ignoring the split, with a large
  A/B letter whose position is configurable (top / middle / bottom).

### Playback and sync

- Aligned start and **exact seek** on every side; the frame-step leader is the
  highest-FPS side.
- **Drift correction** with hysteresis (≈30 ms deadband, ±3%, ≈700 ms settle) and a
  manual **resync**.
- **Frame stepping** with the arrow keys; step size configurable (1, 2 or 5 frames).
- **Hold to jog**: keep an arrow key pressed — forward plays a continuous jog,
  backward repeats exact frame steps. Hold speed configurable (10–100%).
- **`Shift`+arrows** nudge ±1 s, **`Ctrl`+arrows** nudge ±5 s (shown as a toast).
- **Playback speed** 0.25×–2.0× (slider; quick presets).
- **Per-side mute** and global mute. When two videos carry audio, one side is muted
  automatically with a toast.
- **Buffer profile** (small 64 MB / normal 150 MB / large 512 MB) and a per-side
  **buffer indicator**.
- A **"Syncing…"** spinner next to the splitter while a seek/decode settles.
- **Playback diagnostic modal** when a file fails to open: check the libmpv engine
  and copy a full diagnostic report, or pick another file.

### Overlays (HUD)

- **FPS** and **frame** per side while stepping (or always, via setting).
- **Buffer** indicator and **drift meter** (Δ A↔B in ms).
- **Full per-video statistics** overlay (file, resolution/codec/FPS, frame, time,
  buffer, volume/audio).
- Overlay position configurable on the **vertical axis** (top / center / bottom /
  corner) and **horizontal axis** (left / center / right / corner).

### Performance / quality

- **Video scaling**: Bilinear (lightest), Bicubic (balanced), Lanczos (best).
- **Video sync**: Audio (default), Display resample (smooth), Desync (less GPU).
- **Hardware decoding**: Off (software), Compatible (auto-copy), Direct (maps to
  auto-copy on Windows).
- **Drop late frames** (`framedrop`) and **motion interpolation**.

### Capture

- **Copy comparison image** to the clipboard (PNG).
- **Save comparison** as a PNG file, composed in Dart following the current layout
  and spans.

### Window, language and updates

- **Remember app size and position** (portable, stored next to the executable).
- **Fullscreen** with `F`/`F11`; `Esc` exits fullscreen or closes the open modal.
- **Reactive i18n**: Português (pt-BR), English (en-US), Español (es-ES) — instant
  switching.
- **Update check**: queries the latest GitHub Release in the background on startup;
  Settings shows the current version, the status, a **Check for updates** button and
  a **Download update** link, with a small badge on the settings button.
- Instant tooltips and a custom dark theme (Inter + JetBrains Mono, bundled).

### Shortcuts

| Key | Action |
| --- | --- |
| `Space` | Play / pause |
| `←` / `→` | Step 1 frame (hold to jog forward / step backward) |
| `Shift` + `←` / `→` | Nudge ±1 s |
| `Ctrl` (or `Cmd`) + `←` / `→` | Nudge ±5 s |
| `M` | Mute |
| `F` / `F11` | Fullscreen |
| `Esc` | Close modal / exit fullscreen |

## Downloads

| Artifact | Platform | Notes |
| --- | --- | --- |
| `video-splitview-v0.0.48-windows-x64-setup.exe` | Windows 10/11 x64 | Installer (Inno Setup) |
| `video-splitview-v0.0.48-windows-x64-portable.zip` | Windows 10/11 x64 | Portable — unzip and run `video-splitview.exe` |
| `video-splitview-v0.0.48-ubuntu-x64.deb` | Debian / Ubuntu x64 | `sudo dpkg -i <file>.deb` |
| `video-splitview-v0.0.48-fedora-x64.rpm` | Fedora / RHEL x64 | `sudo dnf install <file>.rpm` |
| `video-splitview-v0.0.48-linux-x64.AppImage` | Linux x64 | Portable; needs GTK3/X11 on the host |

The Windows portable and installer are self-contained (`libmpv-2.dll` is bundled).
The `.deb`/`.rpm` use the system `libmpv`; the AppImage bundles libmpv + ffmpeg.

## Supported formats

`mp4, m4v, webm, mkv, mov, avi, ogv, ogg, ts, mts, m2ts, 3gp, 3g2, flv, wmv, asf,
mpg, mpeg, m2v, vob, mxf, rm, rmvb, divx, f4v` (plus **All files**). Decoding is
handled by libmpv, which ships its own codecs.
