# syphon-mixer

Native macOS Syphon mixer for four live input servers.

## Current Scope

- 4 Syphon input channels using `SyphonMetalClient`
- Per-channel source selector, on/off switch, fader, and scale mode
- Additive RGB compositing controlled by each channel fader
- Output texture size control
- Automatic fit, fill/crop, or stretch mapping to the output texture
- Final mixed texture published as the `syphon-mixer Output` Syphon server
- Separate AppKit control window and output window
- External-display fullscreen routing with main-display preview fallback

Selecting `None` on a channel stops and clears that channel's Syphon client.
Turning a channel `Off` keeps the selected source in the UI but disconnects the
client until the channel is turned back on.

## Build

This repository expects the sibling Syphon framework checkout at:

```bash
../Syphon-Framework
```

Build the app bundle:

```bash
./scripts/build_app.sh
```

Run from SwiftPM during development:

```bash
./scripts/run_app.sh
```

## Notes

The local Xcode installation may require the Metal toolchain before rebuilding
`../Syphon-Framework` from source:

```bash
xcodebuild -downloadComponent MetalToolchain
```

When a prebuilt `../Syphon-Framework/build/Release/Syphon.framework` is present,
the mixer can build and run without rebuilding the framework.
