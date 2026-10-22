-- Batched low-resolution Mode 1 renderer. Windows and main/subscreen color
-- math follow SnesJs; other modes and mosaic retain the reference renderer.
return function(ppu,R)
  local original=ppu.renderLine
  local band,rshift=R.band,R.rshift
  if R.nativeBit then band,rshift=R.nativeBit.band,R.nativeBit.rshift end
  local floor,min,max=math.floor,math.min,math.max
  local pixels,ranks,layers={},{},{}
  local subPixels,subRanks,subLayers={},{},{}
  local rankFor,red,green,blue={},{},{},{}
  local previousColors,previousBrightness={},nil
  local spread={}
  for byte=0,255 do
    local value,weight,n=0,1,byte
    for bit=0,7 do value=value+(n%2)*weight;n=floor(n/2);weight=weight*16 end
    spread[byte]=value
  end
  local function window(p,x,l)
    local a=p.window1Enabled[l]
    local b=p.window2Enabled[l]
    if not a and not b then return false end
    local w1=x>=p.window1Left and x<=p.window1Right
    local w2=x>=p.window2Left and x<=p.window2Right
    if p.window1Inversed[l] then w1=not w1 end
    if p.window2Inversed[l] then w2=not w2 end
    if not b then return w1 elseif not a then return w2 end
    local logic=p.windowMaskLogic[l]
    if logic==0 then return w1 or w2 elseif logic==1 then return w1 and w2
    elseif logic==2 then return w1~=w2 else return w1==w2 end
  end
  local function fetch(p,sx,sy,l,four)
    local x,y=sx,sy
    local big=p.bigTiles[l]
    if big then x=floor(x/2);y=floor(y/2) end
    local address=p.tilemapAdr[l]+floor(band(y,255)/8)*32+floor(band(x,255)/8)
    if band(x,256)~=0 and p.tilemapWider[l] then address=address+1024 end
    if band(y,256)~=0 and p.tilemapHigher[l] then address=address+(p.tilemapWider[l] and 2048 or 1024) end
    local vram=p.vram
    local word=vram[band(address,32767)]
    local flip=band(word,16384)~=0
    local vertical=band(word,32768)~=0
    local row=sy%8;if vertical then row=7-row end
    local number=band(word,1023)
    if big then
      if band(sx,8)==(flip and 0 or 8) then number=number+1 end
      if band(sy,8)==(vertical and 0 or 8) then number=number+16 end
    end
    local base=p.tileAdr[l]+number*(four and 16 or 8)+row
    local a=vram[band(base,32767)]
    local b=four and vram[band(base+8,32767)] or 0
    p.tilemapBuffer[l]=word;p.tileBufferP1[l]=a
    if four then p.tileBufferP2[l]=b end
    return word,a,b,flip
  end
  local function compose(p,line,enabled,windows,out,depth,layerOut)
    for x=0,255 do out[x]=0;depth[x]=100;layerOut[x]=5 end
    if enabled[4] then
      local mask=windows[4] and (p.window1Enabled[4] or p.window2Enabled[4])
      for x=0,255 do
        local pixel=p.spriteLineBuffer[x]
        if pixel~=0 and not (mask and window(p,x,4)) then
          out[x]=pixel;depth[x]=rankFor[16+p.spritePrioBuffer[x]];layerOut[x]=4
        end
      end
    end
    for layer=0,2 do
      if enabled[layer] then
        local sy=line+p.bgVoff[layer]
        local sxStart=p.bgHoff[layer]
        local mask=windows[layer] and (p.window1Enabled[layer] or p.window2Enabled[layer])
        local palette,flip,rank,packed,lastTile
        local four=layer<2
        for x=0,255 do
          local sx=x+sxStart
          local tx=floor(sx/8)
          if tx~=lastTile then
            local word,a,b
            word,a,b,flip=fetch(p,sx,sy,layer,four)
            lastTile=tx;p.lastTileFetchedX[layer]=tx;p.lastTileFetchedY[layer]=sy
            packed=spread[band(a,255)]+2*spread[rshift(a,8)]
            if four then packed=packed+4*spread[band(b,255)]+8*spread[rshift(b,8)] end
            palette=band(rshift(word,10),7)*(four and 16 or 4)
            rank=rankFor[layer*4+band(rshift(word,13),1)]
          end
          if rank<depth[x] and not (mask and window(p,x,layer)) then
            local shift=flip and sx%8 or 7-sx%8
            local pixel=band(rshift(packed,shift*4),15)
            if pixel~=0 then out[x]=palette+pixel;depth[x]=rank;layerOut[x]=layer end
          end
        end
      end
    end
  end
  ppu.renderLine=function(p,line)
    local eligible=p.mode==1 and not p.forcedBlank and not p.pseudoHires
    for i=0,4 do
      if (p.mainScreenEnabled[i] or p.subScreenEnabled[i]) and p.mosaicEnabled[i] and p.mosaicSize>1 then eligible=false end
    end
    if not eligible or line<1 or line>=(p.frameOverscan and 240 or 225) then return original(p,line) end
    if line==1 then p.mosaicStartLine=1 end
    for i=0,3 do p.lastTileFetchedX[i]=-1;p.lastTileFetchedY[i]=-1 end
    p.optHorBuffer[0]=0;p.optHorBuffer[1]=0;p.optVerBuffer[0]=0;p.optVerBuffer[1]=0
    p.lastOrigTileX[0]=-1;p.lastOrigTileX[1]=-1
    local modeIndex=p.layer3Prio and 96 or 12
    for j=0,9 do rankFor[p.layersPerMode[modeIndex+j]*4+p.prioPerMode[modeIndex+j]]=j end
    compose(p,line,p.mainScreenEnabled,p.mainScreenWindow,pixels,ranks,layers)
    local anyMath=false
    for i=0,5 do if p.mathEnabled[i] then anyMath=true end end
    if p.preventMath==3 or (p.preventMath==1 and not p.window1Enabled[5] and not p.window2Enabled[5]) then anyMath=false end
    if anyMath and p.addSub then compose(p,line,p.subScreenEnabled,p.subScreenWindow,subPixels,subRanks,subLayers) end
    local mult=p.brightnessMults[p.brightness]
    local brightnessChanged=mult~=previousBrightness
    for i=0,255 do
      local color=p.cgram[i]
      if brightnessChanged or previousColors[i]~=color then
        red[i]=floor(band(color,31)*mult)%256
        green[i]=floor(band(rshift(color,5),31)*mult)%256
        blue[i]=floor(band(rshift(color,10),31)*mult)%256
        previousColors[i]=color
      end
    end
    previousBrightness=mult
    local out,row=p.pixelOutput,line*1536
    for x=0,255 do
      local color=pixels[x];local layer=layers[x]
      local r,g,b=red[color],green[color],blue[color]
      local inWindow=false
      if p.colorClip==1 or p.colorClip==2 or (anyMath and (p.preventMath==1 or p.preventMath==2)) then inWindow=window(p,x,5) end
      local clip=p.colorClip==3 or (p.colorClip==2 and inWindow) or (p.colorClip==1 and not inWindow)
      local mathOn=anyMath and p.mathEnabled[layer] and (layer~=4 or color>=192)
        and not (p.preventMath==2 and inWindow) and not (p.preventMath==1 and not inWindow)
      if mathOn then
        local raw=p.cgram[color]
        r=clip and 0 or band(raw,31);g=clip and 0 or band(rshift(raw,5),31);b=clip and 0 or band(rshift(raw,10),31)
        local useSub=p.addSub and subLayers[x]<5
        local r1,g1,b1=p.fixedColorR,p.fixedColorG,p.fixedColorB
        if useSub then local second=p.cgram[subPixels[x]];r1=band(second,31);g1=band(rshift(second,5),31);b1=band(rshift(second,10),31) end
        local sign=p.subtractColors and -1 or 1
        r=r+sign*r1;g=g+sign*g1;b=b+sign*b1
        if p.halfColors and (useSub or not p.addSub) then r=floor(r/2);g=floor(g/2);b=floor(b/2) end
        r=floor(max(0,min(31,r))*mult)%256
        g=floor(max(0,min(31,g))*mult)%256
        b=floor(max(0,min(31,b))*mult)%256
      elseif clip then r=0;g=0;b=0 end
      local i=row+x*6
      out[i]=r;out[i+1]=g;out[i+2]=b;out[i+3]=r;out[i+4]=g;out[i+5]=b
    end
    R.clearArray(p.spriteLineBuffer)
    p:evaluateSprites(line)
  end
end
