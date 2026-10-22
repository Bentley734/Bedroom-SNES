// PPU oracle: use the pinned, unmodified upstream JavaScript implementation.
const fs=require('fs'),vm=require('vm'),path=require('path');
const context={clearArray:a=>a.fill(0),log() {}};vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(process.argv[2],'snes','pipu.js'),'utf8'),context);
const cases=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
function hash(array,start,count) {let h=0;for(let i=start;i<start+count;i++)h=(h*33+array[i])%4294967296;return h;}
const results=[];
for(const test of cases) {
  const p=new context.Ppu({});Object.assign(p,test.state);
  for(const [name,values] of Object.entries(test.arrays))for(let i=0;i<values.length;i++)p[name][i]=values[i];
  let seed=test.seed;
  function rand(n) {seed=(seed*1664525+1013904223)%4294967296;return Math.floor(seed/65536)%n;}
  for(let i=0;i<32768;i++)p.vram[i]=rand(65536);
  for(let i=0;i<256;i++)p.cgram[i]=rand(32768);
  for(const stage of test.lines) {
    Object.assign(p,stage.state);p.vram[stage.address]=stage.word;p.cgram[stage.palette]=stage.color;
    for(let x=0;x<256;x++){p.spriteLineBuffer[x]=x%3===0?0:128+rand(128);p.spritePrioBuffer[x]=rand(4);}
    p.renderLine(stage.line);
    results.push({pixels:hash(p.pixelOutput,stage.line*1536,1536),
      coordsX:hash(p.mode7Xcoords,0,256),coordsY:hash(p.mode7Ycoords,0,256),
      hor:Array.from(p.optHorBuffer),ver:Array.from(p.optVerBuffer),orig:Array.from(p.lastOrigTileX),
      rangeOver:p.rangeOver,timeOver:p.timeOver});
  }
}
process.stdout.write(JSON.stringify(results));
