Bedroom SNES v0.2.1 fixes the recolored SNES picture and menus, removes the on-screen gameplay controls/HUD, and scales the cartridge to the largest integer size that fits its window.

- Full RGB presentation bypasses Pokemon palette remapping and the final post-processing chain while this mod owns the screen.
- Centered, nearest-neighbor integer scaling uses physical window pixels, including DPI scaling, horizontal hires and overscan. Black borders fill unused space.
- Keyboard/controller controls remain available. Tap/click the picture or press Escape/P to pause; Backspace returns directly to the bedroom. Launch instructions explain how to exit.
- Pause-menu hit testing follows the resized presentation.

Validated through the real Gen1Recomp renderer with forced palette zones and an enabled shader path, three window sizes, DPI placement, unchanged RGB samples, and matching menu colors. Native sandbox, launch, input, storage and exit tests pass for Red/Blue/Yellow on engines 0.3.54 and 0.3.95. The SNES emulation core is unchanged from v0.2.0.

Only the original MIT demo cartridge is bundled; supply your own ROMs.
