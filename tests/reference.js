// Differential oracle. Requires the pinned SnesJs checkout, never a game ROM.
const fs=require('fs'),vm=require('vm'),path=require('path');
const root=process.argv[2],rom=process.argv[3];
const context={log(){},getByteRep:v=>v.toString(16),getWordRep:v=>v.toString(16),getLongRep:v=>v.toString(16),clearArray:a=>a.fill(0),console};
vm.createContext(context);
for(const name of ['cpu','pipu','spc','dsp','apu','cart','snes'])vm.runInContext(fs.readFileSync(path.join(root,'snes',name+'.js'),'utf8'),context);
function snap(obj){
  let out={};for(const key of Object.keys(obj)){
    if(key==='data')continue;
    const v=obj[key];
    if(typeof v==='number'||typeof v==='boolean'||typeof v==='string')out[key]=v;
    else if(v&&v.constructor&&/^(Uint|Int|Float)\d+Array$/.test(v.constructor.name)){
      let h=0;for(let i=0;i<v.length;i++)h=(h*33+Math.trunc(v[i]*((v.constructor.name.startsWith('Float'))?1000000:1)))>>>0;
      out[key]={length:v.length,hash:h};
    }
  }return out;
}
const m=new context.Snes();m.loadRom(new Uint8Array(fs.readFileSync(rom)),false);m.cart.sram=new Uint8Array(0);m.cart.sramSize=0;m.reset(true);
const frames=[];
for(const mask of [0,0,128,128,8,0]){
  m.joypad1State=mask;m.runFrame(false);
  frames.push(Object.fromEntries([['system',m],['cpu',m.cpu],['ppu',m.ppu],['apu',m.apu],['spc',m.apu.spc],['dsp',m.apu.dsp],['cart',m.cart]].map(([k,v])=>[k,snap(v)])));
}
const opcodes={};
for(const [name,Ctor] of [['cpu',context.Cpu],['spc',context.Spc]]){
  const results=[];
  for(let flags=0;flags<4;flags++)for(let op=0;op<256;op++){
    let writes=[];
    const mem={read:a=>a===0x8000?op:(a*13+7)&255,write:(a,v)=>writes.push([a,v])};
    const c=new Ctor(mem);c.br[name==='cpu'?4:0]=0x8000;
    if(name==='cpu'){
      c.br[0]=0x9a5b;c.br[1]=0x11;c.br[2]=0x27;c.br[3]=0x1ff;c.br[5]=0x100;c.setP(flags===0?0:flags===1?0x31:flags===2?0xff:0x08);
      c.e=false;
    }else{
      c.r[0]=0x5b;c.r[1]=0x11;c.r[2]=0x27;c.r[3]=0xef;c.setP(flags===0?0:flags===1?0x31:flags===2?0xff:0x08);
    }
    c.cyclesLeft=0;c.cycle();results.push({state:snap(c),writes});
  }opcodes[name]=results;
}
// Deterministic audible DSP test: looping BRR pulse with direct gain.
const dsp=new context.Dsp({ram:new Uint8Array(65536)}),ram=dsp.apu.ram;
ram[0x200]=0;ram[0x201]=3;ram[0x202]=0;ram[0x203]=3;
ram[0x300]=0xc3;for(let i=1;i<9;i++)ram[0x300+i]=i<5?0x77:0x99;
for(const [a,v] of [[0x5d,2],[0x0c,127],[0x1c,127],[0x00,127],[0x01,127],[0x02,0],[0x03,0x10],[0x04,0],[0x05,0],[0x07,0x7f],[0x6c,0x20],[0x5c,0],[0x4c,1]])dsp.write(a,v);
for(let i=0;i<512;i++)dsp.cycle();
process.stdout.write(JSON.stringify({frames,opcodes,audio:{left:Array.from(dsp.samplesL.slice(0,512)),right:Array.from(dsp.samplesR.slice(0,512)),state:snap(dsp)}}));
