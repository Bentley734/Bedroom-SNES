-- All-mode renderer comparisons. Random data exposes flips, priority, address
-- wrapping and transparent pixels without depending on commercial cartridges.
local env=console.env
local fast,reference=env.new(env.Ppu,{}),env.new(env.Ppu,{})
local fallback=fast.renderLine
fast.renderLine=function(p,line)
  assert(line<1 or line>=(p.frameOverscan and 240 or 225),'visible line used reference renderer')
  return fallback(p,line)
end
include('core/fast_ppu.lua')(fast,env)
fast.getColor=function() error('reference color resolver called') end
fast.getPixelForLayer=function() error('reference pixel resolver called') end
fast.fetchTileInBuffer=function() error('reference tile decoder called') end
fast.generateMode7Coords=function() error('reference affine generator called') end
local seed=72391
local function rand(n) seed=(seed*1664525+1013904223)%4294967296;return math.floor(seed/65536)%n end
local function both(name,value) fast[name]=value;reference[name]=value end
local function array(name,i,value) fast[name][i]=value;reference[name][i]=value end
local checks=0
for mode=0,7 do
  for trial=0,63 do
    both('mode',mode);both('forcedBlank',false)
    both('brightness',rand(16));both('layer3Prio',rand(2)==0)
    both('mode7ExBg',trial%2==0);both('directColor',trial%3~=0)
    both('pseudoHires',trial%5==0);both('interlace',trial%2==0);both('evenFrame',trial%3==0)
    both('frameOverscan',trial%2==0);both('mosaicSize',trial%16+1);both('mosaicStartLine',1)
    both('colorClip',trial%4);both('preventMath',math.floor(trial/4)%4)
    both('addSub',trial%3~=0);both('subtractColors',trial%2==0);both('halfColors',trial%3==0)
    both('fixedColorR',rand(32));both('fixedColorG',rand(32));both('fixedColorB',rand(32))
    both('mode7A',rand(65536)-32768);both('mode7B',rand(65536)-32768)
    both('mode7C',rand(65536)-32768);both('mode7D',rand(65536)-32768)
    both('mode7X',rand(8192)-4096);both('mode7Y',rand(8192)-4096)
    both('mode7Hoff',rand(8192)-4096);both('mode7Voff',rand(8192)-4096)
    both('mode7FlipX',trial%2==0);both('mode7FlipY',trial%3==0)
    both('mode7LargeField',trial%3~=0);both('mode7Char0fill',trial%2==0)
    for i=0,32767 do array('vram',i,rand(65536)) end
    for i=0,255 do array('cgram',i,rand(32768)) end
    for i=0,5 do
      array('window1Enabled',i,rand(2)==0);array('window2Enabled',i,rand(2)==0)
      array('window1Inversed',i,rand(2)==0);array('window2Inversed',i,rand(2)==0)
      array('windowMaskLogic',i,rand(4));array('mathEnabled',i,rand(2)==0)
      if i<5 then
        array('mainScreenEnabled',i,rand(4)~=0);array('subScreenEnabled',i,rand(2)==0)
        array('mainScreenWindow',i,rand(2)==0);array('subScreenWindow',i,rand(2)==0)
        array('mosaicEnabled',i,rand(2)==0)
      end
      if i<4 then
        array('bigTiles',i,rand(2)==0);array('bgHoff',i,rand(1024));array('bgVoff',i,rand(1024))
        array('tilemapAdr',i,rand(32)*1024);array('tileAdr',i,rand(8)*4096)
        array('tilemapWider',i,rand(2)==0);array('tilemapHigher',i,rand(2)==0)
      end
    end
    for _,line in ipairs({1,7,63,127,224,239}) do
      both('forcedBlank',line==127 and trial%7==0)
      both('window1Left',rand(256));both('window1Right',rand(256))
      both('window2Left',rand(256));both('window2Right',rand(256))
      both('brightness',rand(16));both('mosaicStartLine',line==63 and 80 or 1)
      array('vram',rand(32768),rand(65536));array('cgram',rand(256),rand(32768))
      for x=0,255 do
        array('spriteLineBuffer',x,rand(3)==0 and 0 or 128+rand(128));array('spritePrioBuffer',x,rand(4))
      end
      fast:renderLine(line);reference:renderLine(line)
      if line<(fast.frameOverscan and 240 or 225) then
        for i=line*1536,line*1536+1535 do
          assert(fast.pixelOutput[i]==reference.pixelOutput[i], 'mode '..mode..' trial '..trial..' line '..line..' byte '..i..': '..tostring(fast.pixelOutput[i])..' ~= '..tostring(reference.pixelOutput[i]))
        end
        if mode==7 then for i=0,255 do
          assert(fast.mode7Xcoords[i]==reference.mode7Xcoords[i] and fast.mode7Ycoords[i]==reference.mode7Ycoords[i],'affine coordinate mismatch')
        end end
        if mode==2 or mode==4 or mode==6 then for i=0,1 do
          assert(fast.optHorBuffer[i]==reference.optHorBuffer[i] and fast.optVerBuffer[i]==reference.optVerBuffer[i] and fast.lastOrigTileX[i]==reference.lastOrigTileX[i],'offset state mismatch')
        end end
        checks=checks+1
      end
      assert(fast.rangeOver==reference.rangeOver and fast.timeOver==reference.timeOver,'sprite overflow mismatch')
    end
  end
end
print('PASS: '..checks..' all-mode scanlines match without reference rendering: 2/4/8bpp, direct color, offset scrolling, hires/interlace, Mode 7, mosaic, windows and blending')
