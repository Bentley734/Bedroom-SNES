Bedroom SNES v0.2.0 reaches 60 FPS in the tested Super Mario World first-level scene while retaining the pure-Lua SnesJs core.

| Supplied cartridge | Native paced gameplay result |
|---|---|
| Super Mario World (USA) | 60.0 FPS: 900 frames in 15.0006 seconds |
| Super Mario All-Stars (USA), SMB1 World 1-1 | 58.4 FPS: 876 frames in 15.0080 seconds |
| Yoshi's Island (USA, Rev 1) | Unsupported: requires Super FX |

Movement, jumping, audio, graphics and exit were tested. These are short Windows x64 first-level measurements, not full-game certification. The emulator still inherits SnesJs' missing DSP echo, approximate timing and other accuracy limits. Other platforms remain unverified.

Changes:
- Faster native-Lua clock/CPU/SPC dispatch, allocation-free address returns, and event-bounded CPU/DMA/HDMA countdowns.
- Packed background and sprite decoding; optimized Mode 1 windows, clipping and subscreen color math. Size-one mosaic no longer falls back to slow rendering.
- Bounded catch-up pacing, a fixed SNES clock independent of Pokemon speed settings, and all 534 stereo samples queued per frame with a small jitter buffer.
- Existing launch instructions, Backspace/controller/touch exit controls and slow-performance bedroom dialogue remain available.

Validation: 1,776 PPU and 1,664 sprite scanlines, 1,728 partial scheduler comparisons, both dispatch paths across 2,048 CPU/SPC opcode/flag cases, six full-frame snapshots and 512 stereo DSP samples. All 21 Mario World, 23 All-Stars and 18 Zombies reference checkpoints match. Production sandbox/native tests pass for Red, Blue and Yellow on Gen1Recomp 0.3.54 and 0.3.95.

Only the original MIT-licensed demo cartridge is bundled. Supply your own ROMs. No native emulator, extra permissions or Snes9x-Z code is included. The checksum asset verifies the release ZIP.
