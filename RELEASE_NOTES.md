Bedroom SNES v0.1.1 improves Mode 1 rendering performance in the pure-Lua SnesJs emulator.

- Decode each background once per scanline and batch sprite/background priority resolution with reusable buffers.
- Share palette and brightness conversion across each scanline, preserving raster changes and fixed-color math.
- Keep the reference path for unsupported rendering configurations; retain sprite evaluation/overflow timing.
- Exit instructions, immediate Backspace exit, controller/touch exit menus and the sustained-low-FPS bedroom dialogue remain available.

A privately supplied Zombies Ate My Neighbors (USA) ROM improved from 9.6–9.9 FPS in the v0.1.0 native graphics/audio test to 22.1–23.0 FPS at the same first-level movement/shooting checkpoints. These short Windows measurements show a substantial gain, but gameplay is still below full speed and audio can stutter. Other platforms remain unverified.

Validation includes 1,008 accelerated/reference scanlines, 2,048 CPU/SPC cases, six full reference frames, 512 audible stereo DSP samples, scheduler and cartridge tests, plus all 18 private-ROM checkpoints through frame 3,008. Native sandbox/graphics/storage/exit tests pass for Red, Blue and Yellow on Gen1Recomp 0.3.54 and 0.3.95.

Inspired by batching and redundant-work removal in the user-supplied Snes9x-Z source archive. No code from that archive is included. This release remains single-threaded, uses the pinned SnesJs accuracy model, and adds no permissions.

Only the original MIT-licensed demo cartridge is bundled. The SHA-256 asset verifies the mod ZIP.
