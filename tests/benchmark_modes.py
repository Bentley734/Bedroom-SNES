"""All-mode PPU-only throughput. Optional prior fast_ppu.lua for comparison.

Rates exclude CPU/APU, audio, texture uploads and the host game. Compare runs
on the same idle host; they are not whole-game frame rates.
"""
import json, statistics, sys, time
from pathlib import Path
from run import ROOT, runtime

results={}
for mode in range(8):
    for effects in (False,True):
        lua=runtime()
        lua.globals()[b'demo']=(ROOT/'roms/bedroom-demo.sfc').read_bytes()
        lua.globals()[b'renderer']=(Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'core/fast_ppu.lua').read_bytes()
        lua.globals()[b'mode']=mode;lua.globals()[b'effects']=effects
        lua.execute(b'''
          local c=assert(Console.new(demo));local env=c.env
          p=env.new(env.Ppu,{})
          assert(loadstring(renderer))()(p,env)
          include('core/fast_sprites.lua')(p,env)
          p.mode=mode;p.forcedBlank=false;p.brightness=15
          local seed=17
          local function rand(n) seed=(seed*1664525+1013904223)%4294967296;return math.floor(seed/65536)%n end
          for i=0,32767 do p.vram[i]=rand(65536) end
          for i=0,255 do p.cgram[i]=rand(32768) end
          for i=0,3 do
            p.mainScreenEnabled[i]=true;p.subScreenEnabled[i]=i%2==0
            p.tilemapAdr[i]=8192+i*1024;p.tileAdr[i]=i*4096
            p.bgHoff[i]=i*17;p.bgVoff[i]=i*23
          end
          p.mode7A=181;p.mode7B=-181;p.mode7C=181;p.mode7D=181
          p.mode7X=128;p.mode7Y=128;p.mode7Hoff=64;p.mode7Voff=32
          if effects then
            p.addSub=true;p.halfColors=true;p.directColor=true;p.interlace=true;p.mode7ExBg=true
            p.mode7LargeField=true;p.mode7Char0fill=true;p.mode7FlipX=true
            for i=0,5 do
              p.mathEnabled[i]=true;p.window1Enabled[i]=true;p.window2Enabled[i]=true;p.windowMaskLogic[i]=2
              if i<5 then p.mainScreenWindow[i]=true;p.subScreenWindow[i]=true;p.mosaicEnabled[i]=true end
            end
            p.mosaicSize=3;p.window1Right=191;p.window2Left=96;p.preventMath=2;p.colorClip=1
          end
          function frames(n) for f=1,n do for y=0,225 do
            if effects then p.window1Left=y%64;p.window2Right=255-y%96 end
            p:renderLine(y)
          end end end
          frames(4)
        ''')
        samples=[]
        for _ in range(5):
            start=time.perf_counter();lua.globals()[b'frames'](20)
            samples.append(20/(time.perf_counter()-start))
        results[f'mode{mode}'+('_effects' if effects else '')]={'medianPpuFps':round(statistics.median(samples),2),'samples':samples}
        print(f'Mode {mode} effects={effects}: {statistics.median(samples):.2f} PPU FPS',file=sys.stderr,flush=True)
print(json.dumps(results,indent=2))
