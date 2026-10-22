"""Portable core smoke/semantics tests; commercial ROMs are never fixtures."""
import sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'.tools/balls-lua'))
from lupa.luajit21 import LuaRuntime

def runtime():
    lua=LuaRuntime(unpack_returned_tuples=True,encoding=None)
    def read(path):return (ROOT/path.decode()).read_bytes()
    lua.globals()[b'readSource']=read
    lua.execute(b'''local modules={}
      function include(path)
        if modules[path]==nil then modules[path]=assert(loadstring(readSource(path),'@'..path))() end
        return modules[path]
      end
      Console=include('core/console.lua')(include)
    ''')
    return lua

def main():
    lua=runtime()
    lua.execute(b'''
      local R=include('core/runtime.lua')
      assert(not R.truth(0) and not R.truth(false) and R.truth({}))
      assert(R.band(-1,255)==255 and R.arshift(-8,2)==-2 and R.rshift(-1,1)==2147483647)
      assert(R.rem(-7,3)==-1)
      local a=R.typed('Uint8Array',2);a[0]=258;a[1]=-1;assert(a[0]==2 and a[1]==255)
      local s=R.typed('Int16Array',1);s[0]=65535;assert(s[0]==-1)
      local c,err=Console.new('bad');assert(not c and err)
      print('PASS: numeric semantics, typed memory, invalid cartridge')
    ''')
    print('Core modules compile and initialize.')
    lua.globals()[b'demo']=(ROOT/'roms/bedroom-demo.sfc').read_bytes()
    start=time.perf_counter()
    lua.execute(b'''
      console=assert(Console.new(demo))
      for i=1,4 do console:frame() end
      assert(console.machine.ppu.forcedBlank==false)
      local before=console.machine.ram[0]
      console:setButtons(128)
      for i=1,4 do console:frame() end
      assert(console.machine.ram[0]~=before,'D-pad did not reach the cartridge')
      console:setButtons(8);console:frame();console:frame()
      assert(console.machine.ram[0]==0,'Start did not recenter')
      print('PASS: cartridge boots, PPU unblanks, NMI controller input scrolls/recenters')
    ''')
    print(f'10 emulated frames: {time.perf_counter()-start:.3f}s')
    lua.execute((ROOT/'tests/fast_ppu.lua').read_bytes())
    lua.execute((ROOT/'tests/fast_sprites.lua').read_bytes())
    lua.execute((ROOT/'tests/frontend_timing.lua').read_bytes())
    lua.execute((ROOT/'tests/scheduler.lua').read_bytes())
    lua.execute((ROOT/'tests/cartridges.lua').read_bytes())
if __name__=='__main__':main()
