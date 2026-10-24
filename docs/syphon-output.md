# Syphon Output Notes

## Output Contract

- Publish one final composited BGRA8 color texture as the public Syphon output.
- Keep the output server name stable: `syphon-mixer Output`.
- Use `SyphonFrameChannelColor` for the mixed stream. Depth or auxiliary data should be separate tagged companion streams, not a replacement for color output.
- Treat the Syphon output as the final rendered image. Downstream receivers should not need to reproduce the mixer scale/crop/fader state.

## Texture And Timing

- Render all channels into the configured output texture and publish it unflipped. Syphon input frames arrive bottom-up, so they are flipped vertically as they are composited; the built-in test pattern and the PixelMap active area are already top-down and are drawn as-is.
- Publish once per output frame on the same Metal command buffer used for the final render.
- Keep the texture valid until the command buffer commits. Do not release or overwrite the texture before publish is encoded.
- Avoid CPU readback in the frame loop. Readbacks will quickly break 60 fps output.
- If a source server returns no frame or becomes invalid, skip that channel for the current frame and keep the output server alive.

## Size, Scale, And Crop

- Set output texture size to the target canvas/projector resolution, then scale/crop incoming sources into that texture.
- `Fill / Crop` is best for a fixed full-screen output where edges can be cropped.
- `Fit` is best for channel preview or when the full source frame must remain visible.
- `Stretch` should mainly be used for final preview/present of an already-composited output texture.

## Mixing

- Channel faders are applied before additive RGB compositing.
- The published mixed texture uses the already-composited RGB result. Alpha is not a downstream blend contract.
- Turn a channel off when it should stop consuming Syphon frames. Use `None` when the source should be fully cleared.

## App And Bundle

- Reuse an existing `Syphon.framework` instead of downloading/building it per project.
- Bundle `Syphon.framework` into the app under `Contents/Frameworks`.
- Ad-hoc sign only after copying the executable, `Info.plist`, and framework into the app bundle.
- Keep generated app bundles, build products, downloaded frameworks, and local absolute paths out of git.
