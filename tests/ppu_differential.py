"""Compare all-mode raster effects directly against pinned upstream JavaScript."""
import json, os, random, shutil, subprocess, tempfile
from pathlib import Path
from run import ROOT, runtime

def main():
    rng=random.Random(3729);cases=[]
    for mode in range(8):
        for trial in range(8):
            state=dict(mode=mode,forcedBlank=False,brightness=15,frameOverscan=True,
                directColor=trial%2==0,pseudoHires=trial%3==0,interlace=trial%2==0,evenFrame=trial%3==0,
                layer3Prio=trial%2==0,mode7ExBg=trial%2==0,mosaicSize=trial*2+1,
                colorClip=trial%4,preventMath=(trial//2)%4,addSub=trial%3!=0,halfColors=trial%2==0,
                subtractColors=trial%3==0,fixedColorR=7,fixedColorG=11,fixedColorB=19,
                mode7A=[256,181,-181,128,512,0,32767,-32768][trial],mode7B=-181,
                mode7C=181,mode7D=256,mode7X=128,mode7Y=128,mode7Hoff=64,mode7Voff=-32,
                mode7FlipX=trial%2==0,mode7FlipY=trial%3==0,mode7LargeField=trial%2==0,mode7Char0fill=trial%3==0,
                window1Left=32,window1Right=191,window2Left=96,window2Right=223)
            arrays={}
            for name in ['window1Enabled','window2Enabled','window1Inversed','window2Inversed','mathEnabled']:
                arrays[name]=[bool(rng.randrange(2)) for _ in range(6)]
            arrays['windowMaskLogic']=[rng.randrange(4) for _ in range(6)]
            for name in ['mainScreenEnabled','subScreenEnabled','mainScreenWindow','subScreenWindow','mosaicEnabled']:
                arrays[name]=[bool(rng.randrange(2)) for _ in range(5)]
            # Include unobscured backgrounds, not only random sprite/window coverage.
            if trial<2:
                arrays['mainScreenEnabled']=[True]*4+[False]
                arrays['mainScreenWindow']=[False]*5
                state['colorClip']=0;state['preventMath']=0
            for name in ['bigTiles','tilemapWider','tilemapHigher']:arrays[name]=[bool(rng.randrange(2)) for _ in range(4)]
            arrays['bgHoff']=[rng.randrange(1024) for _ in range(4)]+[0]
            arrays['bgVoff']=[rng.randrange(1024) for _ in range(4)]+[0]
            arrays['tilemapAdr']=[rng.randrange(32)*1024 for _ in range(4)]
            arrays['tileAdr']=[rng.randrange(8)*4096 for _ in range(4)]
            lines=[dict(line=y,state=dict(window1Left=rng.randrange(256),brightness=rng.randrange(16)),
                address=rng.randrange(32768),word=rng.randrange(65536),palette=rng.randrange(256),color=rng.randrange(32768)) for y in [1,7,127,224,239]]
            cases.append(dict(state=state,arrays=arrays,seed=rng.randrange(65536),lines=lines))
    upstream=Path(os.environ.get('SNESJS_SOURCE',ROOT.parent/'.work/snes-research/SnesJs'))
    node=os.environ.get('NODE_BINARY') or shutil.which('node') or 'C:/Users/LSDMTHC/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe'
    with tempfile.TemporaryDirectory() as temp:
        plan=Path(temp)/'ppu.json';plan.write_text(json.dumps(cases),encoding='utf-8')
        expected=json.loads(subprocess.check_output([node,str(ROOT/'tests/reference_ppu.js'),str(upstream),str(plan)]))
    lua=runtime();lua.globals()[b'demo']=(ROOT/'roms/bedroom-demo.sfc').read_bytes()
    lua.execute(b'''
      c=assert(Console.new(demo));env=c.env
      function prepare(seed)
        p=env.new(env.Ppu,{});include('core/fast_ppu.lua')(p,env)
        local n=seed
        function rand(limit) n=(n*1664525+1013904223)%4294967296;return math.floor(n/65536)%limit end
        for i=0,32767 do p.vram[i]=rand(65536) end
        for i=0,255 do p.cgram[i]=rand(32768) end
      end
      function hash(a,start,count) local h=0;for i=start,start+count-1 do h=(h*33+a[i])%4294967296 end;return h end
      function render(line)
        for x=0,255 do p.spriteLineBuffer[x]=x%3==0 and 0 or 128+rand(128);p.spritePrioBuffer[x]=rand(4) end
        p:renderLine(line)
        return hash(p.pixelOutput,line*1536,1536),hash(p.mode7Xcoords,0,256),hash(p.mode7Ycoords,0,256)
      end
    ''')
    index=0
    for case in cases:
        lua.globals()[b'prepare'](case['seed']);p=lua.globals()[b'p']
        for k,v in case['state'].items():p[k.encode()]=v
        for k,values in case['arrays'].items():
            for i,v in enumerate(values):p[k.encode()][i]=v
        for stage in case['lines']:
            for k,v in stage['state'].items():p[k.encode()]=v
            p[b'vram'][stage['address']]=stage['word'];p[b'cgram'][stage['palette']]=stage['color']
            pixels,cx,cy=lua.globals()[b'render'](stage['line'])
            # JS remainder retains the sign for negative affine coordinate hashes.
            want=expected[index]
            assert (pixels,cx,cy)==(want['pixels'],want['coordsX']%4294967296,want['coordsY']%4294967296),(index,case['state']['mode'])
            for key,field in [('hor','optHorBuffer'),('ver','optVerBuffer'),('orig','lastOrigTileX')]:
                if case['state']['mode']!=1:assert [p[field.encode()][i] for i in range(2)]==want[key],(index,key)
            assert p[b'rangeOver']==want['rangeOver'] and p[b'timeOver']==want['timeOver']
            index+=1
    print(f'PASS: {index} all-mode raster scanlines match original JavaScript pixels, affine coordinates, offset state and sprite overflow')

if __name__=='__main__':main()
