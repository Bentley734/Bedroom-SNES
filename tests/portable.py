"""Compile/initialize on plain Lua and exercise the JIT-disabled LÖVE path."""
import sys,importlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'.tools/balls-lua'))
for backend in ['lua51','lua54','luajit21']:
    lua=importlib.import_module('lupa.'+backend).LuaRuntime(unpack_returned_tuples=True,encoding=None)
    lua.globals()[b'readSource']=lambda p:(ROOT/p.decode()).read_bytes()
    lua.globals()[b'demo']=(ROOT/'roms/bedroom-demo.sfc').read_bytes()
    lua.execute(b'''
      local cache={}
      function include(path)
        if not cache[path] then cache[path]=assert((loadstring or load)(readSource(path),'@'..path))() end
        return cache[path]
      end
      local R=include('core/runtime.lua')
      assert(R.band(-1,255)==255 and R.rshift(-1,1)==2147483647 and R.arshift(-8,2)==-2)
      assert(R.band(3.9,255)==3 and R.bor(false,true)==1)
      Console=include('core/console.lua')(include);c=assert(Console.new(demo))
      assert(c.header.name=='BEDROOM SNES DEMO')
      local env=c.env
      local fast,reference=env.new(env.Ppu,{}),env.new(env.Ppu,{})
      include('core/fast_ppu.lua')(fast,env)
      for _,p in ipairs({fast,reference}) do
        p.mode=1;p.forcedBlank=false;p.pseudoHires=true;p.brightness=11
        p.mainScreenEnabled[0]=true;p.subScreenEnabled[0]=true
        p.mosaicEnabled[0]=true;p.mosaicSize=7;p.mathEnabled[0]=true
        p.addSub=true;p.halfColors=true;p.cgram[0]=12345
        p.window1Enabled[5]=true;p.window1Left=73;p.window1Right=219;p.colorClip=2
        for i=0,32767 do p.vram[i]=(i*177+63)%65536 end
        for i=1,255 do p.cgram[i]=(i*97)%32768 end
        p:renderLine(1)
      end
      for i=1536,3071 do assert(fast.pixelOutput[i]==reference.pixelOutput[i],'portable effects mismatch') end
    ''')
    if backend=='luajit21':lua.execute(b'jit.off();c:frame();assert(c.machine.frames==1)')
    print('PASS:',backend,'compiles and initializes; bit semantics and effects pixels match'+('; one full frame with JIT disabled' if backend=='luajit21' else ''))
