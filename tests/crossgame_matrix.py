"""Native cross-generation interaction fixtures; no user's save is booted."""
import json,os,shutil,subprocess
from datetime import datetime,timezone
from pathlib import Path
from prepare_love import ROOT,PROBE
shutil.copyfile(ROOT/'tests/crossgame_native.lua',PROBE/'main.lua')
saved=Path(os.environ['APPDATA'])/'LOVE/bedroom-snes-tests'
results=[]
for game in ['gold','silver','crystal','firered','leafgreen']:
    (PROBE/'engine-test-version.txt').write_text(game)
    (saved/'crossgame-result.txt').unlink(missing_ok=True)
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    run=subprocess.run([str(ROOT.parent/'.tools/love-audio-runtime/love-probe.exe'),str(PROBE)],timeout=60,startupinfo=startup)
    log=(saved/'crossgame-result.txt').read_text(encoding='utf-8')
    print(game,log,sep='\n',flush=True)
    assert run.returncode==0 and 'FAIL:' not in log,(game,log)
    results.append(dict(game=game,checks=len(log.splitlines()),passed=True))
(ROOT/'docs/crossgame-validation.json').write_text(json.dumps(dict(version='0.2.5',engine='0.3.95',testedAt=datetime.now(timezone.utc).isoformat(),matrix=results,
    locations=dict(gen1=dict(map='REDS_HOUSE_2F',x=3,y=5),gen2=dict(map='PLAYERS_HOUSE_2F',x=4,y=2),frlg=dict(map='FR_PLAYERS_HOUSE_2F',x=6,y=5)),
    scope='Production loader, actual Gen2/Gen3 interaction dispatcher and compatibility facade, fixture world/session; native graphics/audio and demo. Does not boot a user save or validate a complete Pokemon playthrough.'),indent=2)+'\n',encoding='utf-8')
