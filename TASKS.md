# Tasks

## Done

- Initial native AppKit/Metal Syphon mixer scaffold
- Four Syphon input channels with source selectors, on/off switches, faders, and scale modes
- Built-in TEST channel with a 1920x1080 color bar/grid pattern, on/off switch, fader, and preview
- Additive compositing for enabled channels
- Output-size controlled Metal render target
- Default-off SonyPark0523 PixelMap mode with 1344x672 active area at x=0, y=0 inside 1920x1080
- Output Flip X / Flip Y for the mixed image, default off, PixelMap area kept in place
- Final mixed Syphon server named `syphon-mixer Output`
- Main-display control window plus selectable external fullscreen output window
- Per-channel live preview panes
- Build script with bundled `Syphon.framework` and ad-hoc codesign verification
- Reusable Syphon framework lookup through `SYPHON_FRAMEWORK_PARENT` and global cache helper
- Syphon output notes in `docs/syphon-output.md`

## Next

- Add per-channel blend modes
- Add MIDI/OSC control mapping for faders and source selection
- Add saved mixer presets
- Add automated multi-source render smoke test
