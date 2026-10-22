"""Prepare an isolated native-runtime probe without changing the installed game."""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT.parent/'.work/snes-research'
PROBE=WORK/'probe'
PROBE.mkdir(exist_ok=True)
for name in ['src','data','assets']:
    shutil.copytree(WORK/'engine'/name,PROBE/name,dirs_exist_ok=True)
shutil.copytree(ROOT.parent/'gen1recomp-0.3.54/tests',PROBE/'tests',dirs_exist_ok=True)
shutil.copytree(ROOT,PROBE/'mods/bedroom_snes',dirs_exist_ok=True,ignore=shutil.ignore_patterns('.git','__pycache__'))
shutil.copyfile(ROOT/'tests/love_main.lua',PROBE/'main.lua')
(PROBE/'conf.lua').write_text("function love.conf(t) t.identity='bedroom-snes-tests';t.window.title='Bedroom SNES validation';t.window.width=640;t.window.height=576;t.console=false end\n")
print(PROBE)
