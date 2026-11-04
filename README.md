# syphon-mixer

Native macOS Syphon mixer for four live input servers plus a built-in test pattern.

## Current Scope

- 4 Syphon input channels using `SyphonMetalClient`
- 1 built-in test pattern channel for external display checks
- Source selector and scale mode for each Syphon input
- On/off switch and fader for every channel, including `TEST`
- Additive RGB compositing controlled by each channel fader
- Output texture size control
- SonyPark0523 PixelMap output mode, available from the control panel
- Output Flip X / Flip Y for the mixed image
- Automatic fit, fill/crop, or stretch mapping to the output texture
- Final mixed texture published as the `syphon-mixer Output` Syphon server
- Separate AppKit control window and output window
- External-display selector with fullscreen routing and main-display preview fallback
- Per-channel live preview panes in the control window

Selecting `None` on a channel stops and clears that channel's Syphon client.
Turning a channel `Off` keeps the selected source in the UI but disconnects the
client until the channel is turned back on.
The `TEST` channel starts off by default, outputs a 1920x1080 color bar/grid
pattern when enabled, and follows the same on/off and fader controls as the
Syphon channels. The fullscreen toggle is always available. Without an external
display the output stays a preview window on the main display; once an external
display is connected, the output goes fullscreen on the selected one.

PixelMap is off by default. Turning PixelMap on keeps the final output
canvas at 1920x1080 and maps the mixed content into the 1344x672 active area at
the top-left origin, x=0, y=0. The inactive area remains black. With PixelMap
off, the mix maps to the full output canvas.

Output Flip X and Flip Y mirror the mixed image horizontally and vertically in
both the Syphon output and the output window. Both start off. With PixelMap on,
the active area stays where it is and only the content inside it is mirrored.
Channel previews are not flipped.

## Build

This repository expects the sibling Syphon framework checkout at:

```bash
../Syphon-Framework
```

The scripts first ask the global `syphon-framework-cache` helper for a reusable
framework location. They then fall back to `../Syphon-Framework/build/Release`.
You can also set `SYPHON_FRAMEWORK_PARENT` to any directory that contains
`Syphon.framework`.

Build the app bundle:

```bash
./scripts/build_app.sh
```

Run tests:

```bash
./scripts/test.sh
```

Run from SwiftPM during development:

```bash
./scripts/run_app.sh
```

Syphon output behavior and operational cautions are documented in
[docs/syphon-output.md](docs/syphon-output.md).

`build_app.sh` builds for this Mac's architecture and signs ad-hoc by default.
`ARCHS="arm64 x86_64"` builds a universal binary, and `SIGN_IDENTITY` signs with
a Developer ID identity.

## Distribute To Other Macs

`scripts/package_release.sh` builds a universal (Apple Silicon and Intel) app,
signs it with the Developer ID Application identity in the keychain, notarizes
and staples it, and writes `dist/SyphonMixer-<version>-macOS-universal.zip`.

Store the notarization credentials once, with an app-specific password for the
Apple ID:

```bash
xcrun notarytool store-credentials syphon-mixer-notary --apple-id <Apple ID> --team-id <Team ID>
```

Then build the release zip:

```bash
./scripts/package_release.sh
```

Bump `version` and `build` in `Sources/SyphonMixer/AppInfo.swift` for each
release. The version also appears in the control window title.

On the other Mac (macOS 13 or later), unzip, move `Syphon Mixer.app` to
`/Applications`, and open it. No Syphon install is needed; the framework is
bundled. Hand over the zip, not the `.app` folder: copying the folder through
Dropbox or other sync tools can break the framework symlinks and the signature.

## Notes

The local Xcode installation may require the Metal toolchain before rebuilding
`../Syphon-Framework` from source:

```bash
xcodebuild -downloadComponent MetalToolchain
```

When a prebuilt `../Syphon-Framework/build/Release/Syphon.framework` is present,
the mixer can build and run without rebuilding the framework.
