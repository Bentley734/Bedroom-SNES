Bedroom SNES v0.2.2 adds substantial CPU performance headroom and fixes cartridge timing under host-frame load, while retaining full color, the clean screen and maximum integer scaling.

- Indexed ROM bytes and direct Lua address decoding for common CPU/audio-CPU modes.
- Palette conversion cached only while CGRAM and brightness match.
- Direct cartridge/pause presentation skips unused Pokemon draw work; previous host rendering is restored on exit.
- Alternating upload textures and wall-clock cartridge pacing, with one shared bounded work allowance.

Local native full-window tests (1570x1268):

| Cartridge scene | Uncapped processing FPS | Paced emulation FPS |
|---|---:|---:|
| Super Mario World, first level | 99–101 | 59.9 |
| All-Stars, SMB1 World 1-1 | 112–121 | 60.0 |
| Zombies, first-level walk/shoot | 130–135 | 60.0 |

Mario World's comparable v0.2.1 uncapped scenes measured 66–68 FPS. Paced tests run 15 seconds with a 144 Hz host-loop target and 3 ms of simulated additional host work. These are controlled Windows fixtures, not a full-game or every-mod configuration guarantee. Inherited SnesJs accuracy limits remain. Indexed ROM bytes use additional RAM.

Validation includes reference instruction and frame/DSP checks; 2,784 CPU and 1,280 SPC decoder cases; randomized PPU, sprite and scheduler comparisons; and native color/scaling, input, storage and exit tests on Gen1Recomp 0.3.54/0.3.95 for Red, Blue and Yellow.

Only the original MIT demo ROM is bundled. Supply your own cartridges.
