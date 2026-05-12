# MacAscii

Native macOS prototype for the ASCII desktop overlay.

This is a Swift Package executable so it can build with the Command Line Tools
already installed on this Mac.

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
Ctrl+Option+Comma       Toggle 10/20 luminance buckets
```

Visual styles currently cycle through amber, dark amber, muted CRT, hybrid edge
tint, invert, cyberpunk, green phosphor, paper ink, blueprint, moonlight, and
thermal edge.

The renderer is currently a first Metal port of the GNOME GLSL path: it samples
one captured screen color per grid cell, quantizes luminance, draws procedural
glyph masks, adds simple gradient edge strokes, and applies the same style modes.
Cell sizes are interpreted in logical screen points so Retina displays do not
make the grid twice as dense as intended.
