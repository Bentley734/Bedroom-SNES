"""Fast-forward the startup drawing, then measure actual fully rendered scenes."""
import sys,time,json,hashlib
from pathlib import Path
from run import runtime,ROOT
from test_cartridge import png
def main():
    rom=Path(sys.argv[1]);plan=json.loads(Path(sys.argv[2]).read_text())
    out=ROOT.parent/'.work/snes-research/private-cartridge-test'
    lua=runtime();lua.globals()[b'rom']=rom.read_bytes()
    lua.execute(b'''
      c=assert(Console.new(rom))
      function advance(n,mask,skip)
        c:setButtons(mask)
        local peak=0
        for i=1,n do
          if skip then c.machine:runFrame(true) else c:frame() end
          local dsp=c.machine.apu.dsp
          for j=0,dsp.sampleOffset-1 do peak=math.max(peak,math.abs(dsp.samplesL[j]),math.abs(dsp.samplesR[j])) end
          dsp.sampleOffset=0
        end
        return peak
      end
      function picture()
        local p=c.machine.ppu.pixelOutput;local rows={}
        for y=1,224 do local row={};for x=0,1535 do row[#row+1]=string.char(p[y*1536+x]) end;rows[#rows+1]=table.concat(row) end
        return table.concat(rows)
      end
    ''')
    results=[]
    for name,count,mask,*rest in plan:
        skip=rest and rest[0];t=time.perf_counter();peak=lua.globals()[b'advance'](count,mask,bool(skip));elapsed=time.perf_counter()-t
        rgb=lua.globals()[b'picture']();m=lua.globals()[b'c'][b'machine']
        row={'stage':name,'frames':count,'skippedVideo':bool(skip),'frameNumber':m[b'frames'],'pc':m[b'cpu'][b'br'][4],
             'spcPc':m[b'apu'][b'spc'][b'br'][0],'seconds':elapsed,'fps':count/elapsed,'audioPeak':peak,'pixelSha256':hashlib.sha256(rgb).hexdigest()}
        results.append(row)
        if not skip:png(out/('scene-'+name+'.png'),rgb,512,224)
        (out/'scene-report.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(row),flush=True)
if __name__=='__main__':main()
