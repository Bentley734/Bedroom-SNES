-- Independently compare optimized sprite pixels, priorities and sticky flags
-- against the translated SnesJs evaluator. OAM is also checked
-- to ensure evaluation never modifies sprite data or the rotation address.
local env=console.env
local fast=env.new(env.Ppu,{})
local reference=env.new(env.Ppu,{})
include('core/fast_sprites.lua')(fast,env)
local seed=827161
local function random(n)
  seed=(seed*1664525+1013904223)%4294967296
  return math.floor(seed/65536)%n
end
local function both(name,value) fast[name]=value;reference[name]=value end
local function word(name,i,value) fast[name][i]=value;reference[name][i]=value end
for i=0,32767 do word('vram',i,random(65536)) end
local cases,range,time=0,0,0
local function compare(line)
  for i=0,255 do word('spriteLineBuffer',i,random(256));word('spritePrioBuffer',i,random(4)) end
  fast:evaluateSprites(line);reference:evaluateSprites(line)
  for i=0,255 do
    assert(fast.spriteLineBuffer[i]==reference.spriteLineBuffer[i], 'sprite pixel mismatch case '..cases..' x '..i)
    assert(fast.spritePrioBuffer[i]==reference.spritePrioBuffer[i], 'sprite priority mismatch case '..cases..' x '..i)
    assert(fast.oam[i]==reference.oam[i],'sprite evaluation modified OAM')
  end
  assert(fast.rangeOver==reference.rangeOver,'sprite count overflow mismatch')
  assert(fast.timeOver==reference.timeOver,'sprite tile overflow mismatch')
  assert(fast.oamAdr==reference.oamAdr,'sprite evaluation modified OAM address')
  if fast.rangeOver then range=range+1 end
  if fast.timeOver then time=time+1 end
  cases=cases+1
end
for trial=1,128 do
  for i=0,255 do word('oam',i,random(65536)) end
  for i=0,15 do word('highOam',i,random(65536)) end
  both('objSize',trial%8);both('objPriority',trial%2==0);both('oamAdr',random(256))
  both('objInterlace',trial%3==0);both('evenFrame',trial%2==0)
  both('sprAdr1',random(8)*4096);both('sprAdr2',(random(4)+1)*4096)
  for _,line in ipairs({0,1,7,8,31,63,127,223,239,255}) do
    word('vram',random(32768),random(65536))
    word('oam',random(256),random(65536));word('highOam',random(16),random(65536))
    both('rangeOver',false);both('timeOver',false)
    compare(line)
  end
end
-- Explicit overflow, wraparound Y, negative X edges, zero and all-one planes.
for _,plane in ipairs({0,65535,32768,1,255,65280}) do
  for i=0,32767 do word('vram',i,plane) end
  for _,size in ipairs({0,3,5,7}) do
    both('objSize',size);both('sprAdr1',28672);both('sprAdr2',16384)
    both('objInterlace',false);both('objPriority',false)
    for _,x in ipairs({0,249,255,256,449,505,506,511}) do
      for i=0,127 do
        word('oam',i*2,x%256+250*256);word('oam',i*2+1,65535)
      end
      for i=0,15 do word('highOam',i,x>=256 and 65535 or 43690) end
      both('rangeOver',false);both('timeOver',false);compare(0)
      -- Sticky status bits must remain set across later empty lines.
      compare(128)
    end
  end
end
assert(range>0 and time>0,'overflow branches were not covered')
print('PASS: '..cases..' sprite scanlines match SnesJs: rotation, overflow, offscreen edges, flips, wrapping, interlace and live memory changes')
