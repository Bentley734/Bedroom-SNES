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
    ''')
    if backend=='luajit21':lua.execute(b'jit.off();c:frame();assert(c.machine.frames==1)')
    print('PASS:',backend,'compiles and initializes; bit semantics match'+('; one full frame with JIT disabled' if backend=='luajit21' else ''))
