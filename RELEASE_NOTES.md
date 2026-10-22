Bedroom SNES v0.1.0 adds an experimental pure-Lua SnesJs emulator to the SNES in the player's Pallet Town bedroom in Pokémon Red, Blue and Yellow.

- Cartridge menu, original homebrew demo, controller/keyboard/touch controls, audio and battery RAM persistence.
- Exit instructions appear before every cartridge launch. Backspace returns immediately to the bedroom; Escape/P opens the pause menu. Controller: right-stick click or Start+Select, then Y. Touch: PAUSE, then Return to room.
- Sustained performance below 20 FPS triggers the player's “I think there's something wrong with my SNES...” line on returning to the bedroom. Warm-up and brief slowdowns are excluded.
- Standard NTSC LoROM/HiROM cartridges up to 4 MiB. Supply your own `.sfc`/`.smc` files in the mod's `roms` folder. Enhancement chips, PAL and save states are unsupported.

Validation: 2,048 CPU/SPC instruction comparisons, six complete reference-frame snapshots, audible stereo DSP comparison, randomized accelerated-renderer and scheduler comparisons, Lua 5.1/5.4 initialization and a JIT-disabled frame. Native sandbox/graphics/storage/exit tests pass for Red, Blue and Yellow on Gen1Recomp 0.3.54 and 0.3.95.

A privately supplied Zombies Ate My Neighbors (USA) ROM reaches the first level with movement, shooting and sound; all 18 sampled checkpoints through frame 3,008 match SnesJs. First-level gameplay is approximately 13 FPS in the core test and 10 FPS with native graphics/audio, so it is not comfortably playable yet. Audio can stutter at low frame rates. Only Windows was tested; other platforms remain unverified.

The release includes only our original MIT-licensed demo cartridge. No commercial ROM or native emulator binary is bundled. The attached SHA-256 file verifies the mod ZIP.
