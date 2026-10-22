import time
from run import runtime,ROOT
lua=runtime()
lua.globals()[b'demo']=(ROOT/'roms/bedroom-demo.sfc').read_bytes()
lua.execute(b'''
  c=assert(Console.new(demo));p=c.env.new(c.env.Ppu,{})
  p.forcedBlank=false;p.mode=1
  for i=0,4 do p.mainScreenEnabled[i]=true end
  events={}
  jit.attach(function(what,tr,fn,pc,err,info)
    if what=='abort' then
      local where=debug.getinfo(fn,'S')
      local key=tostring(err)..' / '..tostring(info)..' / '..(where.short_src or '?')..':'..tostring(where.linedefined)
      events[key]=(events[key] or 0)+1
    end
  end,'trace')
''')
start=time.perf_counter();lua.execute(b'for frame=1,3 do for y=0,224 do p:renderLine(y) end end')
print('Synthetic renderer FPS:',3/(time.perf_counter()-start))
for key,n in sorted(lua.globals()[b'events'].items(),key=lambda kv:-kv[1])[:20]:print(n,key.decode())
