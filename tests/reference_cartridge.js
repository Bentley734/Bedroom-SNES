// Private cartridge diagnostic oracle; no cartridge data is written to the repo.
const fs=require('fs'),vm=require('vm'),path=require('path'),crypto=require('crypto');
const source=process.argv[2],rom=process.argv[3],out=process.argv[4];
const errors=[];
const context={log(v){if(String(v).startsWith('Error'))errors.push(String(v));},getByteRep:v=>v.toString(16),getWordRep:v=>v.toString(16),getLongRep:v=>v.toString(16),clearArray:a=>a.fill(0),console};
vm.createContext(context);
for(const name of ['cpu','pipu','spc','dsp','apu','cart','snes'])vm.runInContext(fs.readFileSync(path.join(source,'snes',name+'.js'),'utf8'),context);
const m=new context.Snes();m.loadRom(new Uint8Array(fs.readFileSync(rom)),false);m.reset(true);
const stages=process.argv[5]?JSON.parse(fs.readFileSync(process.argv[5],'utf8')):[['boot',60,0],['logos',180,0],['title',180,0],['start',2,8],['menu',60,0],['confirm',2,8],['game',180,0],['move_right',60,128],['fire',60,256]];
const results=[];
for(const [stage,count,mask] of stages){
  let peak=0;m.joypad1State=mask;
  for(let i=0;i<count;i++){
    m.runFrame(false);for(let j=0;j<m.apu.dsp.sampleOffset;j++)peak=Math.max(peak,Math.abs(m.apu.dsp.samplesL[j]),Math.abs(m.apu.dsp.samplesR[j]));m.apu.dsp.sampleOffset=0;
  }
  const bytes=Buffer.alloc(512*224*3);for(let y=1;y<=224;y++)for(let x=0;x<1536;x++)bytes[(y-1)*1536+x]=m.ppu.pixelOutput[y*1536+x];
  fs.writeFileSync(path.join(path.dirname(out),'reference-'+stage+'.rgb'),bytes);
  const result={stage,frameNumber:m.frames,pc:m.cpu.br[4],spcPc:m.apu.spc.br[0],audioPeak:peak,pixelSha256:crypto.createHash('sha256').update(bytes).digest('hex')};
  results.push(result);fs.writeFileSync(out,JSON.stringify({results,errors},null,2));console.log(JSON.stringify(result));
}
