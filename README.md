# MacAscii

Native macOS desktop overlay that renders the live screen through multiple
procedural visual modes, including ASCII, retro block, halftone, CRT pixel,
mosaic, matrix rain, and an experimental cyberpunk mode.

This is a Swift Package executable, so it builds with the macOS Command Line
Tools already installed on this machine.

## Build

```sh
swift build
```

Build a clickable app bundle:

```sh
scripts/build-app.sh
```

The app will be created at:

```text
build/MacAscii.app
```

During testing, macOS Screen Recording permission is more reliable if the app is
installed at a stable path:

```sh
INSTALL_TO_APPLICATIONS=1 scripts/build-app.sh
```

That also creates:

```text
/Applications/MacAscii.app
```

For repeated development builds, create a stable local signing identity once:

```sh
scripts/create-local-signing-cert.sh
```

Without that identity, the build script falls back to ad-hoc signing, and macOS
may require Screen Recording permission to be reset after each rebuild.

## Run

```sh
swift run MacAscii
```

Or double-click:

```text
build/MacAscii.app
```

The first run needs macOS Screen Recording permission for the launching app,
usually Terminal for `swift run`, or `MacAscii.app` for the bundled app. If
capture fails, enable permission in System Settings, then restart the process.

## Hotkeys

```text
Ctrl+Option+A           Toggle overlay
Ctrl+Option+Period      Cycle grid size
Ctrl+Option+Apostrophe  Cycle visual style
Ctrl+Option+M           Cycle render mode
Ctrl+Option+Comma       Toggle 10/20 luminance buckets
Ctrl+Option+F           Cycle FPS
Ctrl+Option+Minus       Opacity down
Ctrl+Option+Equal       Opacity up
Ctrl+Option+B           Cycle brightness
Ctrl+Option+C           Cycle contrast
Ctrl+Option+G           Cycle gamma
Ctrl+Option+E           Cycle edge strength
```

## Current Controls

Visual styles:

```text
classic-amber
dark-amber
muted-crt
hybrid-edge-tint
invert
cyberpunk
green-phosphor
paper-ink
blueprint
moonlight
thermal-edge
```

Render modes:

```text
ascii
blocky-retro
halftone
crt-pixel
mosaic
matrix-rain
cyberpunk
```

Grid sizes:

```text
1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 16, 20
```

FPS cycle:

```text
15 -> 30 -> 60 -> 120
```

`120` only appears when the active display reports support for it through
AppKit. On a 60 Hz display the cycle stays at `15 -> 30 -> 60`.

Tone and effect controls:

```text
Brightness: -0.50 to 0.50
Contrast:   0.50 to 2.00
Gamma:      0.50 to 2.00
Edge:       0.00 to 2.00
Opacity:    10% to 100%
```

## Menu Bar App

The bundled app provides:

```text
- Menu bar item
- Toggle overlay
- Cycle render mode, grid, style, luminance, and FPS
- Tone controls
- Edge controls
- Reset visual defaults
- Quit command
```

An on-screen HUD appears when values change from hotkeys or menu actions so the
current render mode, grid, style, FPS, and other live settings are visible
while testing.

## Notes

The overlay samples one captured screen color per grid cell, quantizes tone and
luminance, and then applies a procedural render mode on top of that data. Cell
sizes are interpreted in logical screen points so Retina displays do not make
the grid twice as dense as intended.

Fullscreen overlay coverage works with the app bundle, and Screen Recording
permission is most reliable when testing from `/Applications/MacAscii.app`.
