"""Synthetic full-frame PPU benchmark; no ROM required. Compare medians on one host.

An optional renderer path allows a previous release to be measured with the same
runtime and scene. These rates exclude CPU/APU, uploads and host game work.
"""
import json, statistics, sys, time
from pathlib import Path
from run import ROOT, runtime

results = {}
for scene in ('opaque', 'fixed_color', 'transparency', 'split_transparency', 'window_math', 'raster_windows', 'mosaic', 'pseudo_hires'):
    lua = runtime()
    lua.globals()[b'demo'] = (ROOT/'roms/bedroom-demo.sfc').read_bytes()
    source = Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'core/fast_ppu.lua'
    lua.globals()[b'renderer'] = source.read_bytes()
    lua.globals()[b'scene'] = scene.encode()
    lua.execute(b'''
      local c=assert(Console.new(demo));local env=c.env
      p=env.new(env.Ppu,{})
      assert(loadstring(renderer))()(p,env)
      include('core/fast_sprites.lua')(p,env)
      p.mode=1;p.forcedBlank=false;p.brightness=15
      local seed=17
      local function rand(n) seed=(seed*1664525+1013904223)%4294967296;return math.floor(seed/65536)%n end
      for i=0,32767 do p.vram[i]=rand(65536) end
      for i=0,255 do p.cgram[i]=rand(32768) end
      for i=0,2 do
        p.mainScreenEnabled[i]=true;p.subScreenEnabled[i]=true
        p.tilemapAdr[i]=8192+i*1024;p.tileAdr[i]=i*4096
        p.bgHoff[i]=i*17;p.bgVoff[i]=i*23
      end
      for i=0,5 do p.mathEnabled[i]=scene~='opaque' end
      p.addSub=scene~='fixed_color';p.halfColors=true
      p.fixedColorR=7;p.fixedColorG=11;p.fixedColorB=15
      if scene=='split_transparency' then
        p.mainScreenEnabled[1]=false;p.subScreenEnabled[0]=false;p.subScreenEnabled[2]=false
      end
      if scene=='window_math' or scene=='raster_windows' then
        for i=0,5 do
          p.window1Enabled[i]=true;p.window2Enabled[i]=true;p.windowMaskLogic[i]=2
          if i<5 then p.mainScreenWindow[i]=true;p.subScreenWindow[i]=true end
        end
        p.window1Left=32;p.window1Right=191;p.window2Left=96;p.window2Right=223
        p.preventMath=2;p.colorClip=1
      end
      if scene=='mosaic' then p.mosaicSize=7;for i=0,2 do p.mosaicEnabled[i]=true end end
      p.pseudoHires=scene=='pseudo_hires'
      function frames(n) for f=1,n do for y=0,225 do
        if scene=='raster_windows' then p.window1Left=y%128;p.window2Right=255-y%128 end
        p:renderLine(y)
      end end end
      frames(4)
    ''')
    samples=[]
    for _ in range(5):
        start=time.perf_counter();lua.globals()[b'frames'](40)
        samples.append(40/(time.perf_counter()-start))
    results[scene]={'medianPpuFps':round(statistics.median(samples),2),'samples':samples}
print(json.dumps(results,indent=2))
