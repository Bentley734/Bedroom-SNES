"""Prepare a private native gameplay probe from explicit ROM and input-plan paths."""
import json,sys,shutil
from pathlib import Path
from prepare_love import ROOT,PROBE
rom=Path(sys.argv[1]);plan=Path(sys.argv[2])
assert rom.is_file() and plan.is_file()
json.loads(plan.read_text())
shutil.copyfile(ROOT/'tests/native_gameplay.lua',PROBE/'main.lua')
shutil.copyfile(rom,PROBE/'mods/bedroom_snes/roms/private-test.sfc')
shutil.copyfile(plan,PROBE/'private-plan.json')
print('Prepared isolated native gameplay probe; ROM remains outside the repository.')
