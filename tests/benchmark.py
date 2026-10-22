import time
from run import runtime,ROOT
lua=runtime()
print('Runtime:',lua.eval(b'jit.version'),lua.eval(b'jit.status()'))
lua.globals()[b'demo']=(ROOT/'roms/bedroom-demo.sfc').read_bytes()
lua.execute(b'c=assert(Console.new(demo))')
for name,code in [
    ('full',b'for i=1,15 do c:frame();c.machine.apu.dsp.sampleOffset=0 end'),
    ('without PPU',b'for i=1,15 do c.machine:runFrame(true);c.machine.apu.dsp.sampleOffset=0 end')]:
    t=time.perf_counter();lua.execute(code);elapsed=time.perf_counter()-t
    print(name,round(15/elapsed,2),'FPS')
