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
-- Multi-layer priority, sprites, 16x16 tiles and fixed-color math. Change state
-- between scanlines to catch stale palette, tile, brightness and rank caches.
local seed2=78123
local function rand(n) seed2=(seed2*1664525+1013904223)%4294967296;return math.floor(seed2/65536)%n end
local function both(name,value) fast[name]=value;reference[name]=value end
local function array(name,i,value) fast[name][i]=value;reference[name][i]=value end
for trial=1,96 do
  for i=0,32767 do array('vram',i,rand(65536)) end
  for i=0,255 do array('cgram',i,rand(32768));array('oam',i,rand(65536)) end
  for i=0,15 do array('highOam',i,rand(65536)) end
  both('layer3Prio',trial%2==0);both('brightness',trial%16)
  both('objSize',trial%8);both('objPriority',trial%3==0);both('objInterlace',trial%5==0)
  both('preventMath',trial%4);both('subtractColors',trial%2==0);both('halfColors',trial%3==0)
  both('fixedColorR',rand(32));both('fixedColorG',rand(32));both('fixedColorB',rand(32))
  both('window1Left',rand(128));both('window1Right',128+rand(128))
  array('window1Enabled',5,trial%2==0);array('window1Inversed',5,trial%3==0)
  for i=0,5 do array('mathEnabled',i,rand(2)==0) end
  for i=0,4 do array('mainScreenEnabled',i,rand(4)~=0) end
  for i=0,2 do
    array('bigTiles',i,rand(2)==0);array('bgHoff',i,rand(1024));array('bgVoff',i,rand(1024))
    array('tilemapWider',i,rand(2)==0);array('tilemapHigher',i,rand(2)==0)
    array('tilemapAdr',i,rand(32)*1024);array('tileAdr',i,rand(8)*4096)
  end
  -- Also exercise explicit fallback paths.
  both('addSub',trial%13==0);both('pseudoHires',trial%17==0)
  array('mosaicEnabled',0,trial%19==0);array('mainScreenWindow',1,trial%23==0)
  for _,line in ipairs({0,1,2,7,31,127,223,224,225}) do
    array('cgram',rand(256),rand(32768));array('vram',rand(32768),rand(65536))
    fast:renderLine(line);reference:renderLine(line)
    if line>0 and line<225 then
      for i=line*1536,line*1536+1535 do assert(fast.pixelOutput[i]==reference.pixelOutput[i], 'batched pixel mismatch trial '..trial..' line '..line..' byte '..i) end
    end
    for i=0,255 do
      assert(fast.spriteLineBuffer[i]==reference.spriteLineBuffer[i],'sprite mismatch')
      assert(fast.spritePrioBuffer[i]==reference.spritePrioBuffer[i],'sprite priority mismatch')
    end
    assert(fast.rangeOver==reference.rangeOver and fast.timeOver==reference.timeOver,'overflow mismatch')
  end
end
print('PASS: 864 batched/reference scanlines: multiple layers, sprites, large tiles, fixed-color math, raster changes and fallbacks')
