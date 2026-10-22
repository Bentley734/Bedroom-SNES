"""Run the native sandbox/graphics/storage probe on two engine releases."""
import io,json,shutil,subprocess,zipfile,os
from pathlib import Path
from prepare_love import ROOT,WORK,PROBE
from datetime import datetime,timezone

def main():
    old=WORK/'engine0354';old.mkdir(exist_ok=True)
    if not (old/'src/core/Version.lua').exists():
        with zipfile.ZipFile(ROOT.parent/'gen1recomp-0.3.54-windows.zip') as bundle:
            exe=next(n for n in bundle.namelist() if n.endswith('/gen1recomp.exe'))
            with zipfile.ZipFile(io.BytesIO(bundle.read(exe))) as fused:
                for name in fused.namelist():
                    if name.startswith(('src/','data/','assets/')):fused.extract(name,old)
    exe=ROOT.parent/'.tools/love-audio-runtime/love-probe.exe'
    saved=Path(os.environ['APPDATA'])/'LOVE/bedroom-snes-tests'
    checks=[]
    for engine,path in [('0.3.54',old),('0.3.95',WORK/'engine')]:
        for name in ['src','data','assets']:shutil.copytree(path/name,PROBE/name,dirs_exist_ok=True)
        for game in ['red','blue','yellow']:
            (PROBE/'engine-test-version.txt').write_text(game)
            (saved/'result.txt').unlink(missing_ok=True)
            startup=subprocess.STARTUPINFO();startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
            result=subprocess.run([str(exe),str(PROBE)],timeout=60,startupinfo=startup)
            log=(saved/'result.txt').read_text()
            assert 'FAIL:' not in log and 'battery save bytes survive' in log,(engine,game,log)
            checks.append({'engine':engine,'game':game,'checks':len(log.splitlines()),'passed':True})
            print(f'PASS: Gen1Recomp {engine} / {game}: {len(log.splitlines())} native checks')
    report={'testedAt':datetime.now(timezone.utc).isoformat(),'nativeRuntime':'LÖVE 11.x Windows x64','matrix':checks}
    (ROOT/'docs/native-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    for name in ['library','playing','paused','instructions']:shutil.copyfile(saved/(name+'.png'),ROOT/'docs'/(name+'.png'))
if __name__=='__main__':main()
