"""Compare the Lua port with upstream instruction, frame and audio behavior."""
import sys,json,subprocess,time,os,shutil
from pathlib import Path
from run import runtime,ROOT
NODE=os.environ.get('NODE_BINARY') or shutil.which('node') or 'C:/Users/LSDMTHC/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe'
UPSTREAM=Path(os.environ.get('SNESJS_SOURCE',ROOT.parent/'.work/snes-research/SnesJs'))
def pythonize(v):
    if isinstance(v,bytes):return v.decode()
    if hasattr(v,'items'):return {pythonize(k):pythonize(x) for k,x in v.items()}
    return v
def compare(actual,expected,at=''):
    if isinstance(expected,dict):
        for k,v in expected.items():
            if k not in actual:raise AssertionError(f'{at}.{k}: missing')
            compare(actual[k],v,at+'.'+str(k))
    elif isinstance(expected,list):
        for i,v in enumerate(expected):compare(actual[i+1],v,at+f'[{i}]')
    else:
        if isinstance(expected,float):assert abs(actual-expected)<(1e-6 if at.endswith('.apuCatchCycles') else 1e-8),(at,actual,expected)
        else:assert actual==expected,(at,actual,expected)

def main():
    ref=json.loads(subprocess.check_output([str(NODE),str(ROOT/'tests/reference.js'),str(UPSTREAM),str(ROOT/'roms/bedroom-demo.sfc')]))
    lua=runtime();lua.globals()[b'demo']=(ROOT/'roms/bedroom-demo.sfc').read_bytes()
    lua.execute(b'''
      function snap(obj)
        local out={}
        for k,v in pairs(obj) do
          if type(v)=='number' or type(v)=='boolean' or type(v)=='string' then out[k]=v
          elseif type(v)=='table' and v._kind then
            local h=0;local mult=v._kind=='Float64Array' and 1000000 or 1
            for i=0,v.length-1 do local n=v[i]*mult;n=n<0 and math.ceil(n) or math.floor(n);h=(h*33+n)%4294967296 end
            out[k]={length=v.length,hash=h}
          end
        end
        return out
      end
      console=assert(Console.new(demo));m=console.machine;frames={}
      for _,mask in ipairs({0,0,128,128,8,0}) do
        console:setButtons(mask);console:frame()
        frames[#frames+1]={system=snap(m),cpu=snap(m.cpu),ppu=snap(m.ppu),apu=snap(m.apu),spc=snap(m.apu.spc),dsp=snap(m.apu.dsp),cart=snap(m.cart)}
      end
    ''')
    actual=pythonize(lua.globals()[b'frames']);compare(actual,ref['frames'],'frames')
    print('PASS: six whole frames match CPU, SPC, PPU, DMA, RAM, VRAM, palette, sprites and pixel hashes')
    lua.execute(b'''
      opcodes={}
      for _,name in ipairs({'cpu','spc'}) do
        local results={}
        for flags=0,3 do for op=0,255 do
          local writes={}
          local mem={read=function(_,a) if a==32768 then return op else return (a*13+7)%256 end end,
            write=function(_,a,v) writes[#writes+1]={a,v} end}
          local env=console.env;local c=env.new(name=='cpu' and env.Cpu or env.Spc,mem)
          c.br[name=='cpu' and 4 or 0]=32768
          if name=='cpu' then
            c.br[0]=0x9a5b;c.br[1]=0x11;c.br[2]=0x27;c.br[3]=0x1ff;c.br[5]=0x100
          else c.r[0]=0x5b;c.r[1]=0x11;c.r[2]=0x27;c.r[3]=0xef end
          c:setP(flags==0 and 0 or flags==1 and 0x31 or flags==2 and 0xff or 0x08)
          if name=='cpu' then c.e=false end
          c.cyclesLeft=0;c:cycle();results[#results+1]={state=snap(c),writes=writes}
        end end
        opcodes[name]=results
      end
    ''')
    compare(pythonize(lua.globals()[b'opcodes']),ref['opcodes'],'opcodes')
    print('PASS: all 256 CPU and 256 SPC opcodes match upstream across four flag combinations (2,048 cases)')
    lua.execute(b'''
      local env=console.env;dsp=env.new(env.Dsp,{ram=env.typed('Uint8Array',65536)});local ram=dsp.apu.ram
      ram[0x200]=0;ram[0x201]=3;ram[0x202]=0;ram[0x203]=3;ram[0x300]=0xc3
      for i=1,8 do ram[0x300+i]=i<5 and 0x77 or 0x99 end
      for _,r in ipairs({{0x5d,2},{0x0c,127},{0x1c,127},{0,127},{1,127},{2,0},{3,0x10},{4,0},{5,0},{7,0x7f},{0x6c,0x20},{0x5c,0},{0x4c,1}}) do dsp:write(r[1],r[2]) end
      for i=1,512 do dsp:cycle() end
      audio={left={},right={},state=snap(dsp)}
      for i=0,511 do audio.left[i+1]=dsp.samplesL[i];audio.right[i+1]=dsp.samplesR[i] end
    ''')
    compare(pythonize(lua.globals()[b'audio']),ref['audio'],'audio')
    assert max(abs(x) for x in ref['audio']['left'])>0.01,'Audio fixture is silent'
    print('PASS: 512 audible BRR/DSP stereo samples and DSP state match upstream')
if __name__=='__main__':main()
