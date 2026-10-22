"""Render an explicit private-ROM input plan; write evidence only to its output directory."""
import sys,json,time,hashlib
from pathlib import Path
from run import runtime
from test_cartridge import png

def main():
    rom,plan_path,out=map(Path,sys.argv[1:4]);out.mkdir(parents=True,exist_ok=True)
    plan=json.loads(plan_path.read_text());lua=runtime();lua.globals()[b'rom']=rom.read_bytes()
    lua.execute(b'''c=assert(Console.new(rom))
    function advance(n,mask)
      c:setButtons(mask);local peak=0
      for frame=1,n do c:frame();local d=c.machine.apu.dsp
        for i=0,d.sampleOffset-1 do peak=math.max(peak,math.abs(d.samplesL[i]),math.abs(d.samplesR[i])) end
        d.sampleOffset=0
      end
      return peak
    end
    function picture()
      local p=c.machine.ppu.pixelOutput;local rows={}
      for y=1,224 do local row={};for x=0,1535 do row[x+1]=string.char(p[y*1536+x]) end;rows[y]=table.concat(row) end
      return table.concat(rows)
    end''')
    results=[]
    for name,frames,mask,*_ in plan:
      t=time.perf_counter();peak=lua.globals()[b'advance'](frames,mask);seconds=time.perf_counter()-t
      m=lua.globals()[b'c'][b'machine'];rgb=lua.globals()[b'picture']()
      row={'stage':name,'frameNumber':m[b'frames'],'pc':m[b'cpu'][b'br'][4],'spcPc':m[b'apu'][b'spc'][b'br'][0],
           'audioPeak':peak,'pixelSha256':hashlib.sha256(rgb).hexdigest(),'seconds':seconds,'frames':frames}
      results.append(row);png(out/(name+'.png'),rgb,512,224)
      (out/'result.json').write_text(json.dumps({'results':results},indent=2)+'\n')
      print(json.dumps(row),flush=True)
if __name__=='__main__': main()
