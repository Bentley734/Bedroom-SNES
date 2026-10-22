import sys,shutil
from pathlib import Path
from prepare_love import ROOT,WORK,PROBE
rom=Path(sys.argv[1])
shutil.copyfile(ROOT/'tests/native_cartridge.lua',PROBE/'main.lua')
shutil.copyfile(rom,PROBE/'mods/bedroom_snes/roms/private-test.sfc')
print('Private native fixture prepared; cartridge stays outside the repository.')
