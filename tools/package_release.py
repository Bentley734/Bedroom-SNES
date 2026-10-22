"""Build and inspect the runtime-only ZIP; never discover ROMs from disk."""
import json,hashlib,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    version=json.loads((ROOT/'manifest.json').read_text())['version']
    dist=ROOT/'dist';dist.mkdir(exist_ok=True)
    output=dist/f'Bedroom-SNES-v{version}.zip'
    files=['manifest.json','main.lua','screen.lua','README.md','LICENSE','THIRD_PARTY.txt','roms/bedroom-demo.sfc','roms/README.txt']
    files+=sorted(str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'core').glob('*.lua'))
    files+=['docs/library.png','docs/playing.png','docs/instructions.png','docs/integer-presentation.png']
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for name in files:
            info=zipfile.ZipInfo('bedroom_snes/'+name,date_time=(2026,10,22,0,0,0))
            info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o644<<16
            data=(ROOT/name).read_bytes()
            if not name.endswith(('.png','.sfc')):data=data.replace(b'\r\n',b'\n')
            archive.writestr(info,data)
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        assert json.loads(archive.read('bedroom_snes/manifest.json'))['version']==version
        cartridges=[n for n in archive.namelist() if n.lower().endswith(('.sfc','.smc'))]
        assert cartridges==['bedroom_snes/roms/bedroom-demo.sfc'],cartridges
        assert archive.read(cartridges[0])==(ROOT/'roms/bedroom-demo.sfc').read_bytes()
    digest=hashlib.sha256(output.read_bytes()).hexdigest()
    (dist/f'Bedroom-SNES-v{version}.sha256').write_text(f'{digest}  {output.name}\n')
    print(f'{output}\nSHA-256: {digest}\n{len(files)} files; only the original demo cartridge is bundled.')
if __name__=='__main__':main()
