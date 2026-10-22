# Bedroom SNES

A **pure-Lua SNES emulator inside Gen1Recomp**, opened by interacting with the SNES in the player's upstairs bedroom in Pallet Town. Supports Pokémon Red, Blue, and Yellow.

**v0.1.0 is an experimental preview.** The included original homebrew cartridge boots and responds to controls. Speed and game compatibility vary; this is not a full-speed, broadly compatible replacement for a standalone emulator. No commercial SNES ROMs are included.

![Bedroom SNES cartridge menu](docs/library.png)
![Original homebrew running inside the emulator](docs/playing.png)

## Install and play

1. Download `Bedroom-SNES-v0.1.0.zip` from [Releases](https://github.com/Bentley734/Bedroom-SNES/releases/latest).
2. Import it using Gen1Recomp's mod manager and enable **Bedroom SNES** for Red, Blue, or Yellow. Gen1Recomp **0.3.54 or newer** is required; native loader/graphics tests cover 0.3.54 and 0.3.95.
3. Go upstairs in the player's house in Pallet Town and interact with the SNES. Select **bedroom-demo** to try the included cartridge.
4. Read the exit instructions shown **before every cartridge launch**, release the launch button, then confirm to play.
5. Press **Backspace** to return straight to the bedroom, or **Escape/P** to open the pause menu. A controller or the on-screen controls also work.

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

The on-screen pad provides all twelve SNES controls. Tap **PAUSE** at the top to open the pause menu. In that menu: Enter/A resumes, Q/B opens the cartridge menu, Backspace/Y returns to the bedroom, R resets the cartridge, and M toggles sound. The demo uses the D-pad to scroll its picture and Start to recenter it.

If a session stays below **20 emulated FPS** for three consecutive two-second measurement windows after the warm-up windows, the player comments on returning to the bedroom: **“I think there's something wrong with my SNES...”** Pauses and launch/loading time are excluded. Normal performance and brief slowdowns do not trigger the line.

Battery-backed cartridge RAM saves automatically about every 30 seconds of active screen time and on pause/exit. Saves use Gen1Recomp's per-mod storage, scoped to the Pokémon game and playthrough, with the cartridge's SHA-256 as its key. Renaming an identical cartridge does not create a different save. Reset preserves cartridge RAM. **Save states are not implemented.**

## Compatibility and performance

- The core is adapted from [SnesJs](https://github.com/angelo-wf/SnesJs), commit `b904fdb63be15dc0470b69091622ba5b1bde7275`, under the MIT license. It is not a port of Snes9x or ZSNES.
- Includes the 65816 CPU, scanline PPU, SPC700, partial DSP audio, DMA/HDMA, one controller, LoROM/HiROM mapping, and battery RAM.
- Inherits SnesJs' incomplete CPU emulation-mode behavior, approximate timing, graphics edge cases and missing DSP echo. Enhancement chips, PAL timing, high-resolution interlace output, save states and multiplayer are outside this preview.
- One field of interlaced video is shown at a time. Horizontal hires pixels are retained. Some effects will render incorrectly.
- The emulator is time-sliced to keep its menu responsive. Slow devices run cartridges below full speed; audio can stutter. Removing unnecessary numeric conversions substantially improved the LuaJIT renderer. A privately supplied **Zombies Ate My Neighbors (USA)** cartridge was tested through the first level, movement and shooting: the core matched SnesJs' image hashes, CPU program counters and audio peaks at 18 sampled checkpoints through frame 3,008. Its intro/title scenes measured roughly **50–88 FPS**, but moving/shooting in the first level measured only **about 13 FPS** before frontend overhead and **about 10 FPS** in the native graphics/audio test. It is **not comfortably playable in this preview**. These are local test measurements, not platform guarantees; no commercial cartridge is included in the mod or source repository.
- Uses Lua 5.1-compatible source, LÖVE graphics/audio and the standard `bit` library when available. An arithmetic bit fallback exists. No FFI, native emulator binary, external emulator process, network access or platform-specific emulator dependency is used. Windows was tested; other platforms are unverified.
- The `engine_internals` permission is used for the engine music and touch-overlay integration. The mod composes the bedroom's map-script interaction and owns a normal game state while playing.

## Validation and development

`tests/run.py` covers the original test cartridge's boot, PPU, NMI/controller interaction, invalid cartridge bounds, copier headers, LoROM/HiROM, SRAM persistence, 144 randomized accelerated/reference scanlines, and 60 frames of idle scheduler/IRQ comparisons. `tests/differential.py` compares the Lua port against the pinned JavaScript source: all 256 CPU and 256 SPC opcodes in four flag configurations (2,048 cases), six complete machine/frame snapshots, and 512 audible stereo DSP samples. These establish translation behavior, not hardware accuracy or commercial-game compatibility.

`tests/love_main.lua` exercises the production mod loader and sandbox, bedroom MapScripts, native graphics/audio, raw input capture, all twelve touch control routing, pause/resume, repeat entry/exit, storage, save-failure handling and restoration of normal input/touch controls. Native fixtures do not launch a user's save file.

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

The source translator intentionally handles only this core's JavaScript subset and fails on unsupported syntax. It preserves 32-bit bitwise semantics, typed-array wrapping, zero-based indexing, switch fallthrough, default arguments and JavaScript truthiness. Numeric bit operands use LuaJIT's standard bit functions directly; source expressions requiring boolean coercion or truncation keep explicit conversions. Explicit typed writes, multiple color return values and a narrow, tested Mode 1 renderer reduce Lua overhead. WAI idle periods stop at PPU/IRQ/refresh event boundaries. SPC faults propagate to the frontend's error screen instead of being silently swallowed.

See [THIRD_PARTY.txt](THIRD_PARTY.txt) and [LICENSE](LICENSE). The original demo source and generated cartridge are also MIT-licensed.
