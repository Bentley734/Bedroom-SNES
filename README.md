# Bedroom SNES

A **pure-Lua SNES emulator inside Gen1Recomp**, opened by interacting with the console in the player's upstairs bedroom. Supports Pokémon Red, Blue, Yellow, Gold, Silver, Crystal, FireRed and LeafGreen.

**v0.2.5 is an experimental preview.** The included original homebrew cartridge boots and responds to controls. Speed and game compatibility vary; this is not a full-speed, broadly compatible replacement for a standalone emulator. No commercial SNES ROMs are included.

![Bedroom SNES cartridge menu](docs/library.png)
![Original homebrew running inside the emulator](docs/playing.png)

## Install and play

1. Download `Bedroom-SNES-v0.2.5.zip` from [Releases](https://github.com/Bentley734/Bedroom-SNES/releases/latest).
2. Import it using Gen1Recomp's mod manager and enable **Bedroom SNES** for the game you want to play. Gen1Recomp **0.3.54 or newer** is required; Red/Blue/Yellow native loader/graphics tests cover 0.3.54 and 0.3.95; the five added games are tested on 0.3.95 and need its cross-generation compatibility hooks.
3. Go upstairs in the player's house and interact with the console: **Pallet Town** in Red/Blue/Yellow and FireRed/LeafGreen, or **New Bark Town** in Gold/Silver/Crystal. G/S/C needs a console decoration placed in the room. Select **bedroom-demo** to try the included cartridge.
4. Read the exit instructions shown **before every cartridge launch**, release the launch button, then confirm to play.
5. Press **Backspace** to return straight to the bedroom, or **Escape/P** to open the pause menu. Controller pause and exit controls also work.

![Exit instructions shown before launching](docs/instructions.png)

### Add your own cartridges

Copy your own uncompressed `.sfc` or `.smc` files into the installed mod's **`roms/` directory**, next to `bedroom-demo.sfc`. Reopen the cartridge menu (or press R in it) to refresh the list. The mod reads only its own folder. Depending on the platform, use the app's file-sharing tools or add the files to the ZIP before importing it. This preview does not provide a system file picker or download games.

Accepted cartridges: standard **NTSC LoROM and HiROM**, 32 KiB–4 MiB in power-of-two sizes, with or without a 512-byte copier header. Enhancement-chip cartridges and PAL cartridges are rejected with an explanation. Header validation cannot establish that an entire cartridge is valid or compatible.

## Controls

SNES keyboard controls apply while a cartridge is playing; the normal Pokémon controls resume on exit.

| SNES control | Keyboard | SDL gamepad |
|---|---|---|
| D-pad | Arrow keys | D-pad / left stick |
| B / A | Z / X | B / A |
| Y / X | A / S | Y / X |
| L / R | Q / E | Left / right shoulder |
| Start | Enter | Start |
| Select | Shift / Tab | Back / Select |
| Pause | Escape / P | Right-stick click, or hold Start + Select |
| Return straight to bedroom | Backspace | Pause, then Y |

Gameplay has no on-screen controls or HUD. Tap/click the picture to open the pause menu. Use a keyboard or controller to play. In that menu: Enter/A resumes, Q/B opens the cartridge menu, Backspace/Y returns to the bedroom, R resets the cartridge, and M toggles sound. The demo uses the D-pad to scroll its picture and Start to recenter it.

If a session stays below **20 emulated FPS** for three consecutive two-second measurement windows after the warm-up windows, the player comments on returning to the bedroom: **“I think there's something wrong with my SNES...”** Pauses and launch/loading time are excluded. Normal performance and brief slowdowns do not trigger the line.

Battery-backed cartridge RAM saves automatically about every 30 seconds of active screen time and on pause/exit. Saves use Gen1Recomp's per-mod storage, scoped to the Pokémon game and playthrough, with the cartridge's SHA-256 as its key. Renaming an identical cartridge does not create a different save. Reset preserves cartridge RAM. **Save states are not implemented.**

## Compatibility and performance

- The core is adapted from [SnesJs](https://github.com/angelo-wf/SnesJs), commit `b904fdb63be15dc0470b69091622ba5b1bde7275`, under the MIT license. It is not a port of Snes9x or ZSNES.
- Includes the 65816 CPU, scanline PPU, SPC700, partial DSP audio, DMA/HDMA, one controller, LoROM/HiROM mapping, and battery RAM.
- Inherits SnesJs' incomplete CPU emulation-mode behavior, approximate timing, graphics edge cases and missing DSP echo. Enhancement chips, PAL timing, high-resolution interlace output, save states and multiplayer are outside this preview.
- One field of interlaced video is shown at a time. Horizontal hires pixels are retained. Some effects will render incorrectly.
- The emulator shares a bounded work allowance with the host and catches up small frame delays. **Super Mario World (USA)** sustained **60.0 FPS** (900 frames / 15.0006 seconds) in a native paced first-level test with movement, jumping, graphics and audio. **Super Mario All-Stars (USA), Super Mario Bros. 1 World 1-1**, measured **58.4 FPS** (876 frames / 15.0080 seconds). Uncapped native tests measured roughly 66–72 FPS for Mario World and 65–66 FPS for All-Stars. **Yoshi's Island (USA, Rev 1) is unsupported** because it requires Super FX. These are short local Windows measurements, not full-game or other-platform guarantees; inherited SnesJs accuracy limits still apply. See `docs/mario-validation.json` for complete evidence. The earlier Zombies measurements in `docs/rom-validation.json` describe v0.1.1; v0.2.0 also passes its 18 reference checkpoints.
- Uses Lua 5.1-compatible source, LÖVE graphics/audio and the standard `bit` library when available. An arithmetic bit fallback exists. No FFI, native emulator binary, external emulator process, network access or platform-specific emulator dependency is used. Windows was tested; other platforms are unverified.
- The `engine_internals` permission is used for the engine music and touch-overlay integration. The mod composes the bedroom's map-script interaction and owns a normal game state while playing.

## Validation and development

`tests/run.py` covers original-demo boot/input, cartridge validation, SRAM, 5,232 PPU scanlines (including all eight graphics modes, windows, subscreen math, mosaic, direct color, per-tile scrolling, hires/interlace and Mode 7), 1,664 sprite scanlines, 60 scheduler frames, 1,728 partial scheduler/state comparisons, frame pacing, and the complete 534-sample stereo audio queue. `tests/differential.py` checks both reference and optimized CPU/SPC dispatch against all 2,048 opcode/flag cases, six full machine/frame snapshots and 512 audible stereo DSP samples. Private-ROM runs render every frame and match 21 Mario World, 23 All-Stars and 18 Zombies checkpoints for image hashes, CPU/SPC positions and audio peaks. These establish agreement with SnesJs, not physical-hardware accuracy.

`tests/love_main.lua` exercises the production mod loader and sandbox, bedroom MapScripts, native graphics/audio, raw input capture, tap-to-pause and resized pointer routing, pause/resume, repeat entry/exit, storage, save-failure handling and restoration of normal input/touch controls. Native fixtures do not launch a user's save file.

Developer dependencies: Python with `lupa` (LuaJIT backend), Node.js for the differential oracle, and a LÖVE 11.x runtime plus Gen1Recomp sources/test fixtures for the native test. `tests/prepare_love.py` documents this workspace's isolated probe setup. Run from the repository root:

```text
python tests/run.py
python tests/differential.py
python tests/benchmark.py
```

The checked-in Lua core is the runtime source. Rebuild it with Python `esprima==4.0.1` and the exact upstream checkout:

```text
python tools/port_core.py /path/to/SnesJs
python tools/build_demo.py
python tools/package_release.py
```

The source translator intentionally handles only this core's JavaScript subset and fails on unsupported syntax. It preserves 32-bit bitwise semantics, typed-array wrapping, zero-based indexing, switch fallthrough, default arguments and JavaScript truthiness. Numeric bit operands use LuaJIT's standard bit functions directly; source expressions requiring boolean coercion or truncation keep explicit conversions. Explicit typed writes, multiple color/address return values and tested all-mode native Lua rendering reduce Lua overhead. CPU, DMA and HDMA countdowns stop at PPU/IRQ/refresh event boundaries. The hot clock and sprite loops use direct Lua dispatch. SPC faults propagate to the frontend's error screen instead of being silently swallowed.

See [THIRD_PARTY.txt](THIRD_PARTY.txt) and [LICENSE](LICENSE). The original demo source and generated cartridge are also MIT-licensed.

The optimized Mode 1 renderer packs tile bitplanes once per tile row, resolves background/sprite priority with reusable buffers, and supports window masks, clipping, fixed-color and main/subscreen math. As of v0.2.4, all eight background modes use the fast renderer for visible scanlines. Modes 0/1/3 use batched composition; the other modes use packed tile decoding and preserve per-pixel main/subscreen fetch order. The reference handles pre-render and vertical-blank bookkeeping only. Palette conversion is refreshed every scanline; sprite overflow and interlace behavior remain reference-compatible. No Snes9x-Z code was copied; batching and redundant-work removal inspired the optimization. The mod remains single-threaded with no new permissions.

The SNES state opts out of Pokemon speed multipliers. Audio queues all 534 stereo samples per 60 Hz frame and buffers two frames before playback to absorb ordinary timing jitter. Low-performance devices can still stutter; this does not add the upstream core's missing DSP echo.

## Full-color window presentation

v0.2.1 presents the cartridge and menus through the engine composition hook, preserving their RGB colors independently of Pokemon palettes and post-processing. Gameplay uses the largest centered integer scale that fits the window in physical pixels, with nearest-neighbor filtering and black borders. Standard 256-pixel SNES output, horizontal hires and overscan keep their source dimensions. Very small windows that cannot fit even 1x use a reduced fit. There is no on-screen pad, FPS label or pause label. Escape/P pauses, Backspace exits immediately, and tapping/clicking opens the pause menu. The launch instructions still explain exit controls.

Native presentation tests run the real Renderer:endFrame path with forced palettes and an enabled shader path. They check unchanged cartridge RGB, identical menu colors across palette modes, three window sizes, DPI-aware integer placement and resized pause-menu input.

## v0.2.2 performance update

The core now uses indexed cartridge bytes and direct Lua decoders for common 65816/SPC700 address modes. Palette conversion is reused until the actual CGRAM entry or brightness changes; every scanline still checks both. Indexed ROM data increases memory use while a cartridge is loaded.

While a cartridge or its pause menu is topmost, the mod presents directly instead of constructing the unused Pokemon world/UI frame. It restores the previous draw method on exit and keeps the composition-hook fallback. Alternating upload textures reduces sampling/upload contention. Colors, the clean screen and centered integer scaling remain unchanged.

Cartridge timing accrues once per real host frame, independently of Pokemon fixed-step smoothing. The bounded work allowance starts at the first SNES slice and is shared by subsequent catch-up calls. This prevents unrelated host work from consuming the allowance before emulation starts.

In local Windows tests at 1570x1268, Mario World's uncapped native first-level scenes improved from roughly 66–68 FPS in v0.2.1 to 99–101 FPS. All-Stars reached 112–121 FPS and Zombies reached 130–135 FPS in the tested scenes. All three sustained approximately 60 emulated FPS in 15-second paced tests with a 144 Hz host-loop target and an additional simulated 3 ms host delay per update. These controlled fixtures use the production loader, native graphics/audio and the full-size presentation; they are not a benchmark of every enabled mod in a live Pokemon save, every cartridge or other platforms. See `docs/performance-validation.json`.

Additional checks compare 2,784 CPU and 1,280 SPC address-decoder cases against the reference, including address/PC wrapping, cycle penalties and bus-read order. Existing image, instruction, DSP, presentation and exit tests remain in place.

## v0.2.3 effects update

Mode 1 mosaic and pseudo-hires now use the batched renderer instead of falling back to the slower reference renderer. Main/subscreen composition is reused when the enabled layers and window masks are equivalent. Window results are shared by identical masks and refreshed for changes to window bounds, inversion or logic, including changes between scanlines. Bounded lookup tables handle addition/subtraction, half color and brightness without repeating channel conversion at every blended pixel.

Local synthetic PPU-only benchmarks measured about **1.8x** the previous throughput for identical-screen transparency, **2.2x** for static window math, **1.7x** for changing window bounds, and **3.0-3.1x** for mosaic/pseudo-hires. Different-layer transparency improved about **7%**; opaque and fixed-color rendering stayed within **2%** of v0.2.2. These are renderer measurements, not whole-game FPS. Mario World's native first-level test measured roughly **108-111 uncapped FPS**, and **60 FPS** in the 15-second paced fixture. Actual effects scenes and enabled mods can still run slower. See `docs/effects-validation.json` for timings and scope.

The new tests compare 640 additional effects scanlines against the reference, including raster changes to palettes, VRAM, brightness and window registers. Portable Lua 5.1/5.4 and LuaJIT also compare effects output. These checks preserve SnesJs behavior; they do not establish hardware accuracy or fix its remaining timing, Mode 7, interlace and DSP limitations. No frame skipping or effects removal is used.

## v0.2.4 all-mode renderer

All eight SNES background modes now render visible scanlines through optimized Lua, including forced blanking. Modes 0/1/3 batch background composition. Modes 2/4/6 preserve the reference's per-tile offset state and main/subscreen ordering, including the first scrolling tile and masked/occluded pixels. Modes 5/6 keep odd/even horizontal samples and interlace field selection. Mode 7 has native Lua affine-coordinate generation, map wrapping, large-field transparency/fill and extended-background priority. Packed 2/4/8bpp tile rows and direct-color channels feed the shared window, clipping, brightness and blend pipeline. The narrow Mode 1 loop remains specialized to preserve its performance.

Validation adds **2,816** byte-for-byte all-mode scanline comparisons, **320** raster scanlines compared directly with pinned upstream JavaScript (pixels, affine coordinates, scrolling state and sprite overflow), and all-mode effects checks on Lua 5.1/5.4 and LuaJIT. Tests assert visible lines never call the reference renderer or its color/tile/affine helpers. Native fixtures also compare each mode inside the production sandbox on both tested engine versions and all three Pokemon games. Existing cartridge checkpoints, audio, presentation, input, save and exit checks remain in place.

Synthetic PPU-only benchmarks show roughly **1.5x** throughput for ordinary Mode 0 and **2.3x** for Mode 3; the other ordinary modes range from approximately unchanged to **1.4x**. The combined raster-window/mosaic/blend fixtures improve much more because they previously hit especially slow reference paths. These deliberately demanding synthetic cases are not whole-game or live-save FPS measurements. See `docs/modes-validation.json` for all measurements and limitations.

Output is checked against SnesJs, not physical SNES hardware. Its approximate timing, Mode 7/scrolling edge cases, single-field interlace presentation and missing DSP echo remain. No frames or effects are skipped, and Super FX cartridges such as Yoshi's Island remain unsupported.

## v0.2.5 additional Pokemon games

The same mod now supports all eight listed games. Interact with the bedroom console at `REDS_HOUSE_2F` (3,5) in R/B/Y, `PLAYERS_HOUSE_2F` (4,2) in G/S/C, or `FR_PLAYERS_HOUSE_2F` (6,5) in FR/LG. Coordinates identify the object being faced. G/S/C respects the existing console-decoration object: putting the console away leaves the tile inactive. Other bedroom objects and the same coordinates in other rooms keep their normal interactions.

Gen 2/3 use the engine's compatibility interaction seams. Busy scripts/dialogues and moving players cannot open the emulator. The Game3 field is suspended while a private SNES state stack owns input; closing restores the original host stack property and draw function. FR/LG use native BGM pause/resume and their own dialogue UI. All added games draw menus and cartridges directly in full color, with nearest-neighbor integer scaling and the same exit instructions. A save failure keeps the emulator open; quitting to the launcher also cleans up its state and controls.

Native production-loader fixtures exercise all five additions on Gen1Recomp 0.3.95, including actual interaction dispatch, launch, draw, audio, save, input, exit/reentry and slow-session dialogue. They do not boot a user's Pokemon save or establish full-playthrough compatibility. See `docs/crossgame-validation.json`. Red/Blue/Yellow's 282 native checks and the complete emulator regression suites also pass. Cartridge SRAM stays scoped by Pokemon version and playthrough; the emulator core is unchanged from v0.2.4.
