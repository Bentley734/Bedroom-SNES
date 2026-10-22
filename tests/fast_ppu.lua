-- Exercise the accelerated renderer against the unmodified Lua reference.
local env=console.env
local fast=env.new(env.Ppu,{});local reference=env.new(env.Ppu,{})
include('core/fast_ppu.lua')(fast,env)
local seed=12345
local function random(n) seed=(seed*1664525+1013904223)%4294967296;return seed%n end
for trial=1,24 do
  for i=0,32767 do local n=random(65536);fast.vram[i]=n;reference.vram[i]=n end
  for i=0,255 do local n=random(32768);fast.cgram[i]=n;reference.cgram[i]=n end
  for _,p in ipairs({fast,reference}) do
    p.mode=1;p.forcedBlank=false;p.mainScreenEnabled[0]=true
    p.tilemapWider[0]=trial%2==0;p.tilemapHigher[0]=trial%3==0
    p.tilemapAdr[0]=0x2000;p.tileAdr[0]=0
    p.bgHoff[0]=trial*29;p.bgVoff[0]=trial*17;p.brightness=trial%16
    p:renderLine(0)
  end
  for _,line in ipairs({1,7,8,31,127,224}) do
    fast:renderLine(line);reference:renderLine(line)
    for i=line*1536,line*1536+1535 do assert(fast.pixelOutput[i]==reference.pixelOutput[i],'fast renderer pixel mismatch') end
  end
end
print('PASS: accelerated PPU matches reference on 144 randomized scanlines (flips, scroll, palette, priority and map sizes)')
