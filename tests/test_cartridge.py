"""Test an explicitly supplied private cartridge; outputs stay outside the repo."""
import sys,time,json,hashlib,struct,zlib
from pathlib import Path
from run import runtime,ROOT

def png(path,rgb,width,height):
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    rows=b''.join(b'\0'+rgb[y*width*3:(y+1)*width*3] for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b''))

def main():
    source=Path(sys.argv[1]);out=ROOT.parent/'.work/snes-research/private-cartridge-test';out.mkdir(exist_ok=True)
    data=source.read_bytes();lua=runtime();lua.globals()[b'rom']=data
    lua.execute(b'''
      c,problem=Console.new(rom);assert(c,problem)
      function picture()
        local pixels=c.machine.ppu.pixelOutput;local lines={}
        for y=1,224 do
          local row={}
          for x=0,511 do local i=y*1536+x*3;row[#row+1]=string.char(pixels[i],pixels[i+1],pixels[i+2]) end
          lines[#lines+1]=table.concat(row)
        end
        return table.concat(lines)
      end
      function advance(frames,mask)
        c:setButtons(mask)
        local peak=0
        for i=1,frames do
          c:frame()
          local dsp=c.machine.apu.dsp
          for j=0,dsp.sampleOffset-1 do peak=math.max(peak,math.abs(dsp.samplesL[j]),math.abs(dsp.samplesR[j])) end
          dsp.sampleOffset=0
        end
        return peak
      end
    ''')
    console=lua.globals()[b'c'];h=console[b'header']
    header={k:h[k.encode()] for k in ['name','isHirom','chips','romSize','ramSize','region']}
    header={k:v.decode() if isinstance(v,bytes) else v for k,v in header.items()}
    report={'filename':source.name,'sha256':hashlib.sha256(data).hexdigest(),'header':header,'stages':[]}
    print(json.dumps(header),flush=True)
    # Allow startup logos, press Start at the title, then select the first player.
    stages=[('boot',60,0),('logos',180,0),('title',180,0),('start',2,8),('menu',60,0),('confirm',2,8),('game',180,0),('move_right',60,128),('fire',60,256)]
    for name,frames,mask in stages:
        started=time.perf_counter()
        peak=lua.globals()[b'advance'](frames,mask)
        elapsed=time.perf_counter()-started
        m=console[b'machine'];p=m[b'ppu']
        summary={'stage':name,'frames':frames,'seconds':elapsed,'fps':frames/elapsed,'frameNumber':m[b'frames'],'pc':m[b'cpu'][b'br'][4],
                 'ppuMode':p[b'mode'],'forcedBlank':p[b'forcedBlank'],'audioPeak':peak,'pixelSha256':hashlib.sha256(lua.globals()[b'picture']()).hexdigest()}
        report['stages'].append(summary)
        png(out/(name+'.png'),lua.globals()[b'picture'](),512,224)
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(summary),flush=True)
    print(out,flush=True)
if __name__=='__main__':main()
